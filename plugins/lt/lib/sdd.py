#!/usr/bin/env python3
# lt / lib / sdd.py
#
# Motor do ciclo SDD. Reimplementa em Python o que no harness de origem era um binario Go.
#
# POR QUE REIMPLEMENTAR
# A decisao foi espelhar o SDD para dentro do plugin, sem depender de um binario externo. Isso
# significa que estas verificacoes precisam existir aqui: sem elas o ciclo vira prosa, e o
# invariante I-2 (ancora de confianca) nao tem como ser cobrado.
#
# O QUE SE PERDE EM RELACAO AO BINARIO ORIGINAL — dito honestamente, sem alegar paridade:
#   - integracao com runtime ACP externo;
#   - execucao de tarefas pelo proprio motor: `orchestrate` registra o plano, quem executa e'
#     `execute-all-tasks`;
#   - o selo de commit e' opcional e manual, porque o harness nao commita (R-GOV-001).
# O que esta aqui cobre a integridade dos artefatos, o schema de tasks.md, o DAG, a cobertura de
# requisitos, a rastreabilidade requisito -> evidencia, os contratos JSON versionados em
# config/schemas/, o selo de evidencia (secoes + commit opcional), a maquina de estados v2 com
# migracao reversivel, a memoria duravel por PRD e a leitura da telemetria local.
#
# REGRA COMUM A TODOS OS SUBCOMANDOS: gate que nao consegue rodar FALHA ALTO. Nunca devolve
# "ok" por nao ter conseguido verificar.
#
# Uso: python3 sdd.py <subcomando> [args]

import hashlib
import json
import os
import re
import sys

# --- Regexes canonicas da tabela de tarefas -------------------------------------------------
# Sao literais do contrato, nao heuristica. Um `Sim` na coluna Paralelizavel, por exemplo, e'
# erro bloqueante: a coluna so aceita em-dash, "Nao" ou "Com X.Y".
RE_STATUS = re.compile(r"^(pending|in_progress|needs_input|blocked|failed|done)$")
RE_DEPS = re.compile(r"^(—|(\w[\w-]*/)?\d+\.\d+(,\s*(\w[\w-]*/)?\d+\.\d+)*)$")
RE_PARALLEL = re.compile(r"^(—|Não|Com\s+\d+\.\d+(,\s*\d+\.\d+)*)$")
RE_SKILL = re.compile(r"^[a-z0-9-]+$")
RE_TASK_ID = re.compile(r"^\d+\.\d+$")
# O sufixo de letra e' opcional e faz parte do identificador: `RF-09b` e' requisito distinto de
# `RF-09`. Sem ele, `\b` nunca casa entre o digito e a letra e o requisito some da enumeracao:
# o gate de cobertura passava a responder OK com requisito sem tarefa.
RE_RF = re.compile(r"\b(?:RF|REQ)-\d+[a-z]?\b")

HASH_PRD = "spec-hash-prd"
HASH_TECHSPEC = "spec-hash-techspec"
ZERO = "0" * 64

# Categoria de skill sem `category` no frontmatter. Fallback seguro: declaravel por tarefa.
# Vale a pena ser explicito aqui porque o valor e' contrato com a Etapa 4.1 de `create-tasks`.
CATEGORY_FALLBACK = "processual"

ARTIFACTS = ("prd", "techspec", "tasks")
STATES = ("draft", "approved", "stale", "executing", "blocked", "needs_input", "failed", "done")
# Vocabulario das TAREFAS na tabela de tasks.md — diferente do vocabulario dos artefatos acima.
TASK_STATES = ("pending", "in_progress", "needs_input", "blocked", "failed", "done")


def die(msg, code=1):
    sys.stderr.write("[lt sdd] %s\n" % msg)
    raise SystemExit(code)


def sha256_file(path):
    if not os.path.isfile(path):
        die("arquivo nao encontrado: %s" % path)
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_marker(path, key):
    """Le <!-- key: valor --> das primeiras linhas do arquivo."""
    if not os.path.isfile(path):
        return None
    pattern = re.compile(r"<!--\s*%s:\s*([0-9a-f]{64})\s*-->" % re.escape(key))
    with open(path, "r", encoding="utf-8") as fh:
        for _ in range(20):
            line = fh.readline()
            if not line:
                break
            m = pattern.search(line)
            if m:
                return m.group(1)
    return None


def write_marker(path, key, value):
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    pattern = re.compile(r"<!--\s*%s:\s*[0-9a-f]{64}\s*-->" % re.escape(key))
    marker = "<!-- %s: %s -->" % (key, value)
    if pattern.search(text):
        text = pattern.sub(marker, text, count=1)
    else:
        text = marker + "\n" + text
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


# ============================================================================================
# Ancoragem do diretorio de specs — REGRA INEGOCIAVEL
# ============================================================================================
# O `.lt/specs/prd-<slug>/` pertence ao REPOSITORIO EM QUE O COMANDO FOI EXECUTADO, sempre.
#
# Trabalhando em ~/Git/lt-api, a spec nasce em
#   ~/Git/lt-api/.lt/specs/prd-<slug>/
# Trabalhando em ~/Git/lt-dataflow, ela nasce em
#   ~/Git/lt-dataflow/.lt/specs/prd-<slug>/
#
# POR QUE ISSO E' SEGURANCA, NAO ORGANIZACAO
# A spec e' o registro de decisao de uma feature daquele produto. Se ela cair no repo errado:
#   - o PRD de um produto vira historico de outro, e a rastreabilidade RF -> codigo mente;
#   - o `check-spec-drift` compara o requisito de um repo com a implementacao de outro e
#     aprova (ou reprova) por acidente;
#   - o harness passa a acumular spec de cliente dentro do proprio repo de ferramenta, que
#     tem audiencia e ciclo de vida completamente diferentes.
#
# Por isso a resolucao e' explicita e a escrita FORA da raiz detectada e' RECUSADA. Nao ha
# fallback silencioso para o diretorio do plugin, para $HOME nem para /.

import subprocess as _subprocess


def project_root(start=None):
    """Raiz do repositorio onde o comando esta rodando.

    Precedencia:
      1. LT_PROJECT_DIR      — escape hatch explicito, para quem sabe o que esta fazendo
      2. CLAUDE_PROJECT_DIR  — o host ja resolve o projeto da sessao
      3. git rev-parse --show-toplevel a partir do cwd
      4. o proprio cwd
    """
    for env in ("LT_PROJECT_DIR", "CLAUDE_PROJECT_DIR"):
        value = os.environ.get(env)
        if value and os.path.isdir(value):
            return os.path.realpath(value)
    try:
        out = _subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start or os.getcwd(),
            stdout=_subprocess.PIPE, stderr=_subprocess.DEVNULL, timeout=5,
        )
        if out.returncode == 0:
            path = out.stdout.decode("utf-8", "replace").strip()
            if path:
                return os.path.realpath(path)
    except (OSError, _subprocess.SubprocessError):
        pass
    return os.path.realpath(start or os.getcwd())


# Nome do diretorio de specs DENTRO do repo. A raiz e' sempre o repo (project_root acima);
# o que varia e' so o nome da pasta, e ele e' detectado em vez de imposto.
#
# Precedencia:
#   1. LT_TASKS_ROOT          — caminho relativo a raiz do repo, escolha explicita
#   2. AI_TASKS_ROOT          — mesma coisa, nome herdado; os hooks do ciclo ja liam essa
#   3. `tasks_root:` no config do repo — a convencao do repo, versionada
#   4. `.specs/` existente OU versionado no git — respeita o layout que o repo ja usa
#   5. `.lt/specs/`           — padrao do harness
#
# POR QUE DETECTAR EM VEZ DE IMPOR: um repo que ja tem `.specs/` com historico de PRDs nao
# deveria ganhar um segundo diretorio de specs so porque o harness prefere outro nome. Dois
# lugares para a mesma coisa e' como a rastreabilidade comeca a divergir.
#
# POR QUE O GIT ENTRA NA CASCATA: `os.path.isdir` responde pelo CHECKOUT, nao pelo REPO. Um
# worktree recem-criado de um repo que versiona `.specs/` nao tem o diretorio ainda, e a
# deteccao por disco mandava a spec para `.lt/specs/` enquanto o checkout principal usava
# `.specs/` — o mesmo repo com duas raizes de spec, que e' exatamente a divergencia que a
# deteccao existe para evitar.
#
# POR QUE O CONFIG E' A RESPOSTA CANONICA: quando a convencao do repo nao esta versionada no
# proprio diretorio (repo que usa `.specs/` sem commitar), nenhuma arqueologia de disco acerta.
# `tasks_root:` no config resolve de forma deterministica em qualquer checkout.
SPECS_DIR_DEFAULT = os.path.join(".lt", "specs")
SPECS_DIR_LEGACY = ".specs"

# Config do repo consumidor. Os dois caminhos existem porque `0-setup` cria `.lt/config.yaml`
# e as skills documentam `.claude/config.yaml`; ler os dois evita que a escolha do arquivo
# mude o resultado.
CONFIG_RELPATHS = (
    os.path.join(".lt", "config.yaml"),
    os.path.join(".claude", "config.yaml"),
)

RE_TASKS_ROOT = re.compile(r"^\s*tasks_root\s*:\s*(.+?)\s*$")


def _config_tasks_root(root):
    """Le `tasks_root:` do config do repo.

    Parser deliberadamente minimo: o harness nao depende de PyYAML, e a unica chave que
    importa aqui e' um escalar de uma linha. Chave ausente ou arquivo ilegivel = sem opiniao,
    nunca erro — config quebrado nao pode derrubar o ciclo inteiro.
    """
    for rel in CONFIG_RELPATHS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                for line in fh:
                    match = RE_TASKS_ROOT.match(line)
                    if not match:
                        continue
                    value = match.group(1)
                    if "#" in value:
                        value = value.split("#", 1)[0].strip()
                    value = value.strip().strip("'\"").strip()
                    if value:
                        return value
        except (IOError, OSError, UnicodeDecodeError):
            continue
    return None


def _config_spec_repos(root):
    """Le o mapa `spec_repos:` do config do repo.

    Dependencia cross-PRD (`<slug>/<id>`) nasceu resolvendo sempre dentro do MESMO repositorio.
    Isso cobre o caso comum — dois bundles do mesmo produto — e nao cobre o caso real de uma
    feature que atravessa repos: o PRD de quem consome depende do PRD de quem produz, e os dois
    nao podem viver no mesmo lugar sem romper o invariante I-5 (a spec pertence ao repo onde o
    trabalho acontece).

    Declarar o mapa e' o que torna a travessia explicita e auditavel, em vez de adivinhada:

        spec_repos:
          alarmes-criticidade-pipeline: ../dataflow

    Slug ausente do mapa resolve no proprio repo, como antes.
    """
    for rel in CONFIG_RELPATHS:
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            continue
        mapping = {}
        try:
            with open(path, "r", encoding="utf-8") as fh:
                inside = False
                for line in fh:
                    if re.match(r"^\s*spec_repos\s*:\s*$", line):
                        inside = True
                        continue
                    if not inside:
                        continue
                    if line.strip() and not line[:1].isspace():
                        break  # saiu do bloco indentado
                    entry = re.match(r"^\s+([A-Za-z0-9_-]+)\s*:\s*(.+?)\s*$", line)
                    if not entry:
                        continue
                    value = entry.group(2)
                    if "#" in value:
                        value = value.split("#", 1)[0].strip()
                    value = value.strip().strip("'\"").strip()
                    if value:
                        mapping[entry.group(1)] = value
        except (IOError, OSError, UnicodeDecodeError):
            continue
        if mapping:
            return mapping
    return {}


def _tracked_in_git(root, relpath):
    """O caminho e' versionado neste repo, mesmo que ainda nao exista neste checkout?"""
    try:
        out = _subprocess.run(
            ["git", "ls-files", "--", relpath],
            cwd=root,
            stdout=_subprocess.PIPE, stderr=_subprocess.DEVNULL, timeout=5,
        )
    except (OSError, _subprocess.SubprocessError):
        return False
    return out.returncode == 0 and bool(out.stdout.strip())


def specs_root_of(root):
    """Aplica a cascata a uma raiz de repositorio JA conhecida.

    Separado de `specs_root` porque `project_root` honra LT_PROJECT_DIR/CLAUDE_PROJECT_DIR antes
    do argumento — o que esta certo para a sessao atual e errado para perguntar pela raiz de
    specs de OUTRO repositorio (`spec_repos`). Ali a raiz nao se descobre, ja veio dada.

    As variaveis de ambiente de tasks_root tambem NAO se aplicam aqui: elas descrevem a intencao
    do operador para o repo em que ele esta, e vaza-las para o repo vizinho faria o mapeamento
    apontar para uma pasta que so existe na cabeca de quem exportou a variavel.
    """
    configured = _config_tasks_root(root)
    if configured:
        candidate = configured if os.path.isabs(configured) else os.path.join(root, configured)
        return os.path.realpath(candidate)

    legacy = os.path.join(root, SPECS_DIR_LEGACY)
    if os.path.isdir(legacy) or _tracked_in_git(root, SPECS_DIR_LEGACY):
        return legacy

    return os.path.join(root, SPECS_DIR_DEFAULT)


def specs_root(start=None):
    root = project_root(start)

    for env in ("LT_TASKS_ROOT", "AI_TASKS_ROOT"):
        override = os.environ.get(env)
        if override:
            candidate = override if os.path.isabs(override) else os.path.join(root, override)
            return os.path.realpath(candidate)

    return specs_root_of(root)


def prd_dir_arg(path):
    """Normaliza o argumento dos subcomandos que operam sobre o BUNDLE.

    As skills passam ora o diretorio (`.specs/prd-<slug>`), ora um arquivo dentro dele
    (`.specs/prd-<slug>/tasks.md`) — as duas formas aparecem na prosa, e a segunda e' a unica
    citada em `create-tasks` Etapa 4.7. O motor aceitava so' a primeira, entao seguir a
    instrucao escrita produzia "prd.md nao encontrado em .../tasks.md": uma mensagem que
    culpa o artefato quando o errado foi o formato do argumento.

    Arquivo vira o diretorio que o contem. Diretorio passa direto.
    """
    if os.path.isfile(path):
        return assert_within_project(os.path.dirname(os.path.abspath(path)))
    return assert_within_project(path)


def assert_within_project(path):
    """RECUSA operar sobre spec fora da raiz do repositorio atual.

    Este guard existe porque um caminho relativo errado, um `cd` esquecido ou um argumento
    copiado de outra sessao levariam a spec para o repo errado — e o erro so apareceria meses
    depois, na forma de rastreabilidade que nao fecha.
    """
    root = project_root()
    target = os.path.realpath(path)

    home = os.path.realpath(os.path.expanduser("~"))
    if target in (home, os.path.realpath(os.sep)):
        die("RECUSADO: '%s' e' a raiz do HOME ou do sistema. Spec vive dentro de um repositorio."
            % path, 3)

    try:
        common = os.path.commonpath([root, target])
    except ValueError:
        common = ""
    if common != root:
        die(
            "RECUSADO: '%s' esta FORA do repositorio atual.\n"
            "  repositorio detectado : %s\n"
            "  caminho pedido        : %s\n"
            "  O `.lt/specs/` pertence ao repo em que o comando roda. Rode a partir da raiz do\n"
            "  projeto certo, ou aponte LT_PROJECT_DIR explicitamente." % (path, root, target),
            3,
        )
    return target


def cmd_skills_available(argv):
    """Lista as skills REALMENTE instaladas no plugin, com a categoria de cada uma.

    POR QUE ISTO EXISTE: as skills do ciclo referenciam uma camada de linguagem
    (go-implementation, node-implementation, ...) que e' OPCIONAL e pode nao estar instalada.
    Mandar o agente "ler lt:go-implementation" sem checar produz o defeito mais caro deste
    harness — instruir a carregar algo que nao existe — e foi exatamente o que a migracao das
    skills de dados teve de corrigir. Aqui a skill PERGUNTA em vez de supor.

    Saida: uma linha por skill, "<nome>\t<categoria>". Sem skills, saida vazia e exit 0:
    ausencia e' resposta valida, nao erro.
    """
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )
    skills_dir = os.path.join(plugin_root, "skills")
    if not os.path.isdir(skills_dir):
        return 0

    only = None
    if "--category" in argv:
        only = argv[argv.index("--category") + 1]

    for name in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(path):
            continue
        # `category` vive sob `metadata:` porque nao e' chave oficial do SKILL.md — a doc do
        # host lista `metadata` como o lugar para dados customizados. Ler o nivel superior
        # tambem, para tolerar skill escrita antes dessa normalizacao.
        category = ""
        with open(path, "r", encoding="utf-8") as fh:
            inside = False
            in_metadata = False
            for line in fh:
                if line.strip() == "---":
                    if inside:
                        break
                    inside = True
                    continue
                if not inside:
                    continue
                if line.startswith("metadata:"):
                    in_metadata = True
                    continue
                if in_metadata and line[:1] not in (" ", "\t"):
                    in_metadata = False
                stripped = line.strip()
                if stripped.startswith("category:"):
                    category = stripped.split(":", 1)[1].strip()
        # A regra documentada em `create-tasks` Etapa 4.1 e' explicita: campo ausente =
        # `processual`, que e' o fallback seguro (declaravel por tarefa). O filtro comparava com
        # a string crua, entao `--category processual` devolvia VAZIO — e o agente que seguisse a
        # instrucao da skill concluiria que nao existe skill processual nenhuma, justamente
        # quando as candidatas reais (guidelines, slices) sao as que importam.
        effective = category or CATEGORY_FALLBACK
        if only and effective != only:
            continue
        print("%s\t%s" % (name, effective))
    return 0


def cmd_specs_root(argv):
    """Imprime a raiz de specs do repositorio atual. As skills chamam isto em vez de assumir.

    Com `--slug <nome>`, imprime o diretorio completo da spec. Com `--create`, cria a arvore.

    Slug declarado em `spec_repos:` resolve no repo mapeado, nao no atual — e' o que permite uma
    dependencia cross-PRD apontar para outro repositorio sem quebrar o invariante I-5. `--create`
    e' RECUSADO nesse caso: criar spec dentro de outro repo a partir daqui e' exatamente o erro
    que I-5 existe para impedir; o bundle do outro repo nasce la, com o comando rodando la.
    """
    root = specs_root()
    if "--slug" in argv:
        slug = argv[argv.index("--slug") + 1]
        safe = re.sub(r"[^a-z0-9-]+", "-", slug.lower()).strip("-")
        if not safe:
            die("slug invalido: %r" % slug, 2)

        mapped = _config_spec_repos(project_root()).get(safe)
        if mapped:
            if "--create" in argv:
                die("RECUSADO: '%s' esta mapeado em spec_repos para '%s'. Crie o bundle rodando o\n"
                    "  comando DENTRO daquele repositorio — I-5: a spec pertence ao repo do trabalho."
                    % (safe, mapped), 3)
            base = mapped if os.path.isabs(mapped) else os.path.join(project_root(), mapped)
            if not os.path.isdir(base):
                die("spec_repos aponta '%s' para '%s', que nao existe" % (safe, base), 3)
            print(os.path.join(specs_root_of(os.path.realpath(base)), "prd-%s" % safe))
            return 0

        root = os.path.join(root, "prd-%s" % safe)
    if "--create" in argv:
        assert_within_project(root)
        os.makedirs(root, exist_ok=True)
    print(root)
    return 0


def prd_paths(prd_dir):
    return (
        os.path.join(prd_dir, "prd.md"),
        os.path.join(prd_dir, "techspec.md"),
        os.path.join(prd_dir, "tasks.md"),
    )


def state_path(prd_dir):
    return os.path.join(prd_dir, "sdd-state.json")


def load_state(prd_dir):
    # Diretorio ausente nao e' "estado vazio": e' bundle inexistente. Sem esta checagem,
    # `load_state` devolvia o default, o comando seguia, e `save_state` estourava com traceback
    # cru do Python num caminho `.../sdd-state.json.tmp`. O operador via um stack trace em vez
    # de "o bundle nao existe" — e a causa real (spec apagada por um `git reset` num worktree,
    # porque o bundle nunca foi commitado) ficava escondida atras do erro errado.
    if not os.path.isdir(prd_dir):
        die("bundle inexistente: %s\n"
            "  Rode `lt-sdd.sh specs-root --slug <slug> --create` para criar, ou confira se o\n"
            "  diretorio de specs foi removido (bundle nao versionado desaparece em `git clean`\n"
            "  e em reset de worktree — commite `.specs/`/`.lt/specs/`)." % prd_dir, 3)
    path = state_path(prd_dir)
    if not os.path.isfile(path):
        # Bundle novo nasce em v2. Bundle existente em v1 continua sendo lido como esta: a
        # conversao e' `migrate-sdd`, explicita e com backup — nunca efeito colateral de um
        # `approve` qualquer, que reescreveria o estado de quem nem pediu migracao.
        return new_state_v2("manual")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            state = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        die("sdd-state.json ilegivel: %s" % exc)
    if not isinstance(state, dict) or not isinstance(state.get("artifacts", {}), dict):
        die("sdd-state.json fora do formato: esperado objeto com `artifacts`")
    version = state.get("schema_version", 1)
    if version not in (1, 2):
        die("sdd-state.json com schema_version %r desconhecido (suportados: 1, 2)" % version)
    if version == 2:
        errors = state_v2_errors(state)
        if errors:
            die("sdd-state.json v2 invalido:\n  - %s" % "\n  - ".join(errors))
    return state


STATE_VERSION = 2
RE_RUN_ID = re.compile(r"^[A-Za-z0-9._-]+$")


def utc_now():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_state_v2(run_id):
    return {"schema_version": STATE_VERSION, "run_id": run_id, "artifacts": {}, "events": []}


def state_v2_errors(state):
    """Schema do estado v2 + as regras que o subconjunto de schema nao expressa."""
    errors = schema_errors(load_schema("sdd-state.schema.json"), state)
    for name, info in (state.get("artifacts") or {}).items():
        if not isinstance(info, dict):
            continue
        approved = info.get("approved")
        # Status e flag contam a mesma historia ou o estado mente: `approved=true` com status
        # `stale` e' aprovacao que ninguem sabe se ainda vale.
        if (info.get("status") == "approved") != (approved is True):
            errors.append("artefato %s: status %r e approved=%r inconsistentes"
                          % (name, info.get("status"), approved))
        if approved is True and not info.get("hash"):
            errors.append("artefato %s: aprovado sem hash" % name)
    return errors


def record_event(state, action, detail=""):
    """Evento append-only. So existe em v2; v1 nao tem onde guardar e segue como antes."""
    if state.get("schema_version") != STATE_VERSION:
        return
    event = {"at": utc_now(), "action": action}
    if state.get("run_id"):
        event["run_id"] = state["run_id"]
    if detail:
        event["detail"] = detail
    state.setdefault("events", []).append(event)


def set_artifact(state, name, status, digest=None):
    info = state.setdefault("artifacts", {}).get(name) or {}
    info["status"] = status
    if digest:
        info["hash"] = digest
    if state.get("schema_version") == STATE_VERSION:
        info["approved"] = status == "approved"
    state["artifacts"][name] = info
    return info


def save_state(prd_dir, state):
    if state.get("schema_version") == STATE_VERSION:
        errors = state_v2_errors(state)
        if errors:
            # Nunca publicar estado invalido: o proximo `load_state` o recusaria e o bundle
            # ficaria preso atras de um arquivo que o proprio motor escreveu.
            die("RECUSADO: estado v2 resultante e' invalido:\n  - %s" % "\n  - ".join(errors))
    path = state_path(prd_dir)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


# ============================================================================================
# hash
# ============================================================================================
def cmd_hash(argv):
    if not argv:
        die("uso: sdd.py hash <arquivo>", 2)
    print(sha256_file(argv[0]))
    return 0


# ============================================================================================
# sync-spec-hash
# ============================================================================================
def cmd_sync_spec_hash(argv):
    if not argv:
        die("uso: sdd.py sync-spec-hash <dir-do-prd>", 2)
    prd_dir = prd_dir_arg(argv[0])
    prd, techspec, tasks = prd_paths(prd_dir)
    if not os.path.isfile(prd):
        die("prd.md nao encontrado em %s" % prd_dir)

    state = load_state(prd_dir)
    artifacts = state.get("artifacts", {})

    # RECUSA rodar sobre estado aprovado sujo.
    # Sem esta recusa, "sincronizar hash" viraria a forma mais facil de esconder drift real:
    # o artefato mudou, o hash e' reescrito, e a inconsistencia some sem ninguem decidir nada.
    dirty = []
    for name, path in (("prd", prd), ("techspec", techspec)):
        info = artifacts.get(name) or {}
        if info.get("status") == "approved" and os.path.isfile(path):
            if info.get("hash") and info["hash"] != sha256_file(path):
                dirty.append(name)
    if dirty:
        die(
            "RECUSADO: %s esta(o) aprovado(s) mas o conteudo mudou.\n"
            "  Sincronizar o hash agora mascararia drift real.\n"
            "  Caminho correto: `sdd.py invalidate %s --from %s`, reveja e aprove de novo."
            % (", ".join(dirty), prd_dir, dirty[0]),
            3,
        )

    prd_hash = sha256_file(prd)
    changed = []
    if os.path.isfile(techspec):
        write_marker(techspec, HASH_PRD, prd_hash)
        changed.append("techspec.md <- prd")
    if os.path.isfile(tasks):
        write_marker(tasks, HASH_PRD, prd_hash)
        if os.path.isfile(techspec):
            write_marker(tasks, HASH_TECHSPEC, sha256_file(techspec))
        changed.append("tasks.md <- prd, techspec")

    if not changed:
        die("nada a sincronizar: nem techspec.md nem tasks.md existem em %s" % prd_dir)
    for line in changed:
        print("  sincronizado: %s" % line)
    return 0


# ============================================================================================
# check-spec-drift
# ============================================================================================
def cmd_check_spec_drift(argv):
    if not argv:
        die("uso: sdd.py check-spec-drift <dir-do-prd>", 2)
    prd_dir = prd_dir_arg(argv[0])
    prd, techspec, tasks = prd_paths(prd_dir)
    if not os.path.isfile(prd):
        die("prd.md nao encontrado em %s" % prd_dir)

    prd_hash = sha256_file(prd)
    drifts = []
    # Elo so' e' "integro" se foi VERIFICADO. Artefato ausente nao pode ser pulado em silencio e
    # depois coberto por uma mensagem que afirma a cadeia inteira: verde por ausencia e' o
    # falso-positivo que este motor existe para nao produzir.
    checked = []
    pending = []

    if os.path.isfile(techspec):
        recorded = read_marker(techspec, HASH_PRD)
        if recorded is None:
            drifts.append("techspec.md nao grava <!-- %s: ... -->" % HASH_PRD)
        elif recorded == ZERO:
            drifts.append("techspec.md ainda tem o hash placeholder (zeros)")
        elif recorded != prd_hash:
            drifts.append(
                "techspec.md foi derivada de outra versao do prd.md\n"
                "      gravado: %s\n      atual:   %s" % (recorded[:16], prd_hash[:16])
            )
        checked.append("PRD -> TechSpec")
    else:
        pending.append("techspec.md")

    if os.path.isfile(tasks):
        recorded = read_marker(tasks, HASH_PRD)
        if recorded is None:
            drifts.append("tasks.md nao grava <!-- %s: ... -->" % HASH_PRD)
        elif recorded not in (ZERO,) and recorded != prd_hash:
            drifts.append("tasks.md foi derivada de outra versao do prd.md")
        checked.append("PRD -> Tasks")
        if os.path.isfile(techspec):
            recorded_ts = read_marker(tasks, HASH_TECHSPEC)
            ts_hash = sha256_file(techspec)
            if recorded_ts is None:
                drifts.append("tasks.md nao grava <!-- %s: ... -->" % HASH_TECHSPEC)
            elif recorded_ts not in (ZERO,) and recorded_ts != ts_hash:
                drifts.append("tasks.md foi derivada de outra versao da techspec.md")
            checked.append("TechSpec -> Tasks")
    else:
        pending.append("tasks.md")

    if drifts:
        sys.stderr.write("[lt sdd] DRIFT detectado em %s:\n" % prd_dir)
        for d in drifts:
            sys.stderr.write("  - %s\n" % d)
        sys.stderr.write(
            "\n  O invariante I-2 (ancora de confianca) esta rompido: a implementacao nao\n"
            "  descende mais do requisito. Reveja os artefatos e rode `sync-spec-hash`.\n"
        )
        return 1

    if not checked:
        print("sem elo a verificar: so existe prd.md — a cadeia ainda nao foi construida")
    else:
        print("sem drift nos elos verificados: %s" % ", ".join(checked))
    if pending:
        print("  ainda nao existe(m): %s — estes elos NAO foram verificados"
              % ", ".join(pending))
    return 0


# ============================================================================================
# validate-sdd
# ============================================================================================
def parse_tasks_table(path):
    """Extrai as linhas da tabela canonica de tarefas."""
    rows = []
    header_seen = False
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            stripped = line.strip()
            if not stripped.startswith("|"):
                continue
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if not header_seen:
                if cells and cells[0] == "#":
                    header_seen = True
                continue
            if all(set(c) <= set("-: ") for c in cells if c):
                continue
            if len(cells) >= 6 and RE_TASK_ID.match(cells[0]):
                rows.append({
                    "lineno": lineno,
                    "id": cells[0],
                    "title": cells[1],
                    "status": cells[2],
                    "deps": cells[3],
                    "parallel": cells[4],
                    "skills": cells[5],
                })
    return rows


# Contrato SDD versionado. `<!-- sdd-contract: v2 -->` no topo do tasks.md opta o bundle pelo
# contrato v2: alem de schema, DAG e cobertura (v1), o sdd-state.json tem de estar em v2, valido, e
# todo artefato aprovado tem de continuar batendo com os bytes atuais.
#
# AUSENCIA DO MARCADOR = v1. Bundle que existia antes do contrato versionado continua validando
# exatamente como validava: mudar a regra por baixo de quem nao optou transformaria todo bundle
# antigo em vermelho numa atualizacao do plugin.
#
# VERSAO DESCONHECIDA FALHA. `v3` num harness que conhece ate v2 e' um contrato que este motor
# nao sabe cobrar — aprovar seria verde por ignorancia.
RE_SDD_CONTRACT = re.compile(r"<!--\s*sdd-contract\s*:\s*v(\d+)\s*-->", re.IGNORECASE)
SDD_CONTRACTS = (1, 2)


def detect_sdd_contract(tasks_path):
    with open(tasks_path, "r", encoding="utf-8") as fh:
        head = "".join(fh.readline() for _ in range(30))
    match = RE_SDD_CONTRACT.search(head)
    return (int(match.group(1)), "marcador em tasks.md") if match else (1, "sem marcador: historico v1")


def contract_v2_errors(prd_dir):
    errors = []
    if not os.path.isfile(state_path(prd_dir)):
        return ["contrato v2 exige sdd-state.json (aprove os artefatos ou rode migrate-sdd)"]
    state = load_state(prd_dir)
    if state.get("schema_version") != STATE_VERSION:
        return ["contrato v2 exige sdd-state.json v2 (atual: v%s) — rode migrate-sdd"
                % state.get("schema_version", 1)]
    paths = dict(zip(ARTIFACTS, prd_paths(prd_dir)))
    for name, info in sorted((state.get("artifacts") or {}).items()):
        if info.get("approved") and os.path.isfile(paths.get(name, "")):
            if info.get("hash") != sha256_file(paths[name]):
                errors.append("artefato %s aprovado esta stale: conteudo mudou depois da aprovacao "
                              "(rode invalidate --from %s)" % (name, name))
    return errors


def cmd_validate_sdd(argv):
    requested = None
    if "--contract" in argv:
        index = argv.index("--contract")
        if index + 1 < len(argv) and re.match(r"^v\d+$", argv[index + 1]):
            requested = int(argv[index + 1][1:])
            argv = argv[:index + 1] + argv[index + 2:]
    args = _positional(argv)
    if not args:
        die("uso: sdd.py validate-sdd <dir-do-prd> [--contract [v1|v2]]", 2)
    prd_dir = prd_dir_arg(args[0])
    prd, techspec, tasks = prd_paths(prd_dir)
    errors = []

    if not os.path.isfile(tasks):
        die("tasks.md nao encontrado em %s" % prd_dir)

    contract, origin = detect_sdd_contract(tasks)
    if requested is not None:
        contract, origin = requested, "pedido por --contract"
    if contract not in SDD_CONTRACTS:
        die("contrato SDD v%d desconhecido (suportados: %s)"
            % (contract, ", ".join("v%d" % v for v in SDD_CONTRACTS)), 1)
    if "--contract" in argv:
        print("sdd-contract: v%d (%s)" % (contract, origin))

    rows = parse_tasks_table(tasks)
    if not rows:
        # Zero linhas nao e' "tudo certo": ou a tabela nao existe, ou o formato quebrou.
        die("nenhuma linha de tarefa reconhecida em %s — a tabela canonica esta ausente ou fora do formato" % tasks)

    ids = set()
    for row in rows:
        loc = "%s:%d [%s]" % (os.path.basename(tasks), row["lineno"], row["id"])
        if row["id"] in ids:
            errors.append("%s id duplicado" % loc)
        ids.add(row["id"])

        if not RE_STATUS.match(row["status"]):
            # STATES e' o vocabulario dos ARTEFATOS (prd/techspec/tasks), nao o das tarefas.
            # Citar a lista errada aqui ensinaria a correcao errada.
            errors.append("%s Status invalido: %r (esperado: %s)"
                          % (loc, row["status"], "|".join(TASK_STATES)))
        if not RE_DEPS.match(row["deps"]):
            errors.append("%s Dependencias invalido: %r (use em-dash U+2014 quando vazio)"
                          % (loc, row["deps"]))
        if not RE_PARALLEL.match(row["parallel"]):
            errors.append("%s Paralelizavel invalido: %r (so aceita —, 'Não' ou 'Com X.Y'; "
                          "'Sim' e 'talvez' sao erro bloqueante)" % (loc, row["parallel"]))
        if row["skills"] != "—":
            for skill in [s.strip() for s in row["skills"].split(",") if s.strip()]:
                if not RE_SKILL.match(skill):
                    errors.append("%s skill fora do formato kebab: %r" % (loc, skill))

    # Dependencias apontam para tarefa existente (ignorando cross-PRD, que tem prefixo)
    for row in rows:
        if row["deps"] == "—":
            continue
        for dep in [d.strip() for d in row["deps"].split(",")]:
            if "/" in dep:
                continue
            if dep not in ids:
                errors.append("%s:%d [%s] depende de %s, que nao existe na tabela"
                              % (os.path.basename(tasks), row["lineno"], row["id"], dep))

    # Ciclo no DAG
    graph = {}
    for row in rows:
        deps = [] if row["deps"] == "—" else [
            d.strip() for d in row["deps"].split(",") if "/" not in d
        ]
        graph[row["id"]] = deps

    WHITE, GRAY, BLACK = 0, 1, 2
    color = dict((k, WHITE) for k in graph)

    def visit(node, stack):
        color[node] = GRAY
        for dep in graph.get(node, []):
            if dep not in color:
                continue
            if color[dep] == GRAY:
                errors.append("ciclo de dependencia: %s" % " -> ".join(stack + [dep]))
                return
            if color[dep] == WHITE:
                visit(dep, stack + [dep])
        color[node] = BLACK

    for node in sorted(graph):
        if color[node] == WHITE:
            visit(node, [node])

    # Cobertura de requisitos: todo RF do prd.md aparece na tabela de cobertura
    if os.path.isfile(prd):
        with open(prd, "r", encoding="utf-8") as fh:
            prd_text = fh.read()
        rfs = set(m.group(0) for m in RE_RF.finditer(prd_text))
        if rfs:
            with open(tasks, "r", encoding="utf-8") as fh:
                tasks_text = fh.read()
            covered = set(m.group(0) for m in RE_RF.finditer(tasks_text))
            missing = sorted(rfs - covered)
            if missing:
                errors.append(
                    "requisito(s) sem tarefa em '## Cobertura de Requisitos': %s"
                    % ", ".join(missing)
                )

    if contract >= 2:
        errors.extend(contract_v2_errors(prd_dir))

    if errors:
        sys.stderr.write("[lt sdd] validate-sdd FALHOU (%d erro(s)):\n" % len(errors))
        for e in errors:
            sys.stderr.write("  - %s\n" % e)
        return 1

    extra = ", estado v2 e aprovacoes" if contract >= 2 else ""
    print("validate-sdd OK: %d tarefa(s), schema, DAG e cobertura de requisitos integros%s (contrato v%d)"
          % (len(rows), extra, contract))
    return 0


# ============================================================================================
# seal-evidence
# ============================================================================================
# Contrato de evidencia v2. FAIL-CLOSED: criterio sem prova e' REJEITADO.
# "Prosa nao parseada nao e' prova de ausencia" — se o relatorio nao declara os criterios na
# forma canonica, o gate nao pode concluir que estao atendidos.
RE_CRITERION = re.compile(r"^-\s+(?P<crit>.+?)\s+->\s+comprovado:\s+(?P<proof>.+?)\s*$")
REQUIRED_SECTIONS = (
    "## Tarefa",
    "## Comandos Executados",
    "## Arquivos Alterados",
    "## Resultados de Validação",
    "## Critérios de Aceite",
)


def cmd_seal_evidence(argv):
    args = _positional(argv, ("--commit", "--base"))
    if not args:
        die("uso: sdd.py seal-evidence <relatorio_execucao.md> [--commit <sha> [--base <commit>]] [--verify]", 2)
    path = args[0]
    if not os.path.isfile(path):
        die("relatorio nao encontrado: %s" % path)

    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    errors = []
    for section in REQUIRED_SECTIONS:
        # Aceita a forma com e sem acento: um validador que so casa a forma acentuada falha em
        # silencio sob locale diferente, e um que so casa a sem acento rejeita o artefato real.
        alt = section.replace("Validação", "Validacao").replace("Critérios", "Criterios")
        if section not in text and alt not in text:
            errors.append("secao obrigatoria ausente: %s" % section)

    block = None
    for marker in ("## Critérios de Aceite", "## Criterios de Aceite"):
        if marker in text:
            block = text.split(marker, 1)[1]
            break
    if block is not None:
        block = block.split("\n## ", 1)[0]
        bullets = [ln for ln in block.split("\n") if ln.strip().startswith("- ")]
        if not bullets:
            errors.append(
                "'## Critérios de Aceite' sem nenhum item. Fail-closed: a ausencia de criterios "
                "nao e' prova de que foram atendidos."
            )
        for bullet in bullets:
            if not RE_CRITERION.match(bullet.strip()):
                errors.append(
                    "criterio sem prova na forma canonica `- <criterio> -> comprovado: <evidencia>`:\n"
                    "      %s" % bullet.strip()[:100]
                )

    if errors:
        sys.stderr.write("[lt sdd] seal-evidence REJEITADO (%d problema(s)):\n" % len(errors))
        for e in errors:
            sys.stderr.write("  - %s\n" % e)
        sys.stderr.write(
            "\n  Invariante I-4: uma tarefa so e' `done` com evidencia fisica. Criterio sem\n"
            "  prova e' rejeitado, nao tolerado.\n"
        )
        return 1

    print("seal-evidence OK: contrato de evidencia v2 satisfeito em %s" % os.path.basename(path))
    if "--commit" in argv or "--verify" in argv:
        return seal_commit(path, text, _opt(argv, "--commit"), _opt(argv, "--base"), "--verify" in argv)
    return 0


# --- Selo de commit (opcional) -----------------------------------------------------------------
# O harness NAO commita (R-GOV-001). A prova de fechamento e' verificada contra a arvore viva, que
# deixa de existir quando o humano commita. O selo e' o passo opcional que torna a evidencia
# re-auditavel depois: grava no execution-result o commit que contem o trabalho e o SHA-256 do
# patch base..commit. Qualquer auditor recompoe o digest so' com os dois SHAs.
#
# O selo NAO prova que o commit e' byte-identico a arvore do fechamento: essa arvore ja nao existe.
#
# BASE COMO ARVORE: `snapshot` grava base_sha como objeto `tree`, e arvore nao tem ancestralidade.
# Nesse caso a descendencia e' provada contra `--base <commit>` (o commit sobre o qual a tarefa
# comecou), e o digest continua calculado a partir de base_sha — o que torna o --verify
# reproduzivel sem precisar lembrar do --base.
RE_RESULT_PATH = re.compile(r"(?im)^result_path\s*=\s*(\S+)\s*$")


def _git_try(args, cwd):
    proc = _subprocess.run(["git"] + args, cwd=cwd, stdout=_subprocess.PIPE, stderr=_subprocess.PIPE)
    return proc.returncode, proc.stdout


def _seal_patch(root, base, commit, excludes):
    pathspec = ["--", "."] + [":(exclude)%s" % e for e in sorted(set(excludes)) if e]
    pathspec.append(":(glob,exclude)**/.tmp-*")
    code, out = _git_try(["diff", "--binary", base, commit] + pathspec, root)
    if code != 0:
        die("git diff %s..%s falhou — algum dos objetos nao existe neste repositorio" % (base[:12], commit[:12]))
    return out


def seal_commit(report, text, commit, base_commit, verify):
    root = project_root()
    match = RE_RESULT_PATH.search(text)
    if not match:
        die("selo RECUSADO: o relatorio nao declara `result_path=` — nao ha execution-result a selar", 1)
    ref = match.group(1).split("#", 1)[0]
    result_path = os.path.realpath(ref if os.path.isabs(ref) else os.path.join(root, ref))
    if os.path.commonpath([root, result_path]) != root or not os.path.isfile(result_path):
        die("selo RECUSADO: result_path fora do repositorio ou inexistente: %s" % ref, 1)
    with open(result_path, "r", encoding="utf-8") as fh:
        try:
            result = json.load(fh)
        except ValueError as exc:
            die("selo RECUSADO: execution-result ilegivel: %s" % exc, 1)
    errors = result_errors("execution", result)
    if errors:
        die("selo RECUSADO: execution-result invalido:\n  - %s" % "\n  - ".join(errors), 1)

    bundle = os.path.relpath(os.path.dirname(os.path.realpath(report)), root)
    excludes = [bundle, os.path.relpath(result_path, root), result["patch_ref"].split("#", 1)[0]]
    excludes += [e.split("#", 1)[0] for e in result["evidence"]]
    base = result["base_sha"]
    code, kind = _git_try(["cat-file", "-t", base], root)
    kind = kind.decode().strip() if code == 0 else ""
    if kind not in ("commit", "tree"):
        die("selo RECUSADO: base_sha %s nao existe neste repositorio" % base[:12], 1)

    if verify:
        if not result.get("commit_sha"):
            die("verify RECUSADO: a evidencia da tarefa %s nao esta selada" % result["task_id"], 1)
        if kind == "commit" and _git_try(["merge-base", "--is-ancestor", base, result["commit_sha"]], root)[0] != 0:
            die("verify FALHOU: commit %s nao descende de base_sha %s" % (result["commit_sha"][:12], base[:12]), 1)
        digest = hashlib.sha256(_seal_patch(root, base, result["commit_sha"], excludes)).hexdigest()
        if digest != result["commit_patch_sha256"].lower():
            die("verify FALHOU: patch do commit %s diverge do selo registrado\n"
                "  registrado: %s\n  recomputado: %s" % (result["commit_sha"][:12], result["commit_patch_sha256"], digest), 1)
        print("seal-evidence --verify OK: tarefa %s conferida no commit %s" % (result["task_id"], result["commit_sha"][:12]))
        return 0

    if result["status"] != "done":
        die("selo RECUSADO: apenas resultado done pode ser selado (status=%s)" % result["status"], 1)
    if result.get("commit_sha"):
        die("selo RECUSADO: tarefa %s ja selada no commit %s — use --verify"
            % (result["task_id"], result["commit_sha"][:12]), 1)
    code, out = _git_try(["rev-parse", "--verify", "%s^{commit}" % commit], root)
    if code != 0:
        die("selo RECUSADO: commit %r nao resolve" % commit, 1)
    resolved = out.decode().strip()
    if kind == "tree":
        if not base_commit:
            die("selo RECUSADO: base_sha e' uma arvore de snapshot, sem ancestralidade.\n"
                "  Informe --base <commit> (o commit sobre o qual a tarefa comecou).", 1)
        code, out = _git_try(["rev-parse", "--verify", "%s^{commit}" % base_commit], root)
        if code != 0:
            die("selo RECUSADO: --base %r nao resolve para commit" % base_commit, 1)
        ancestor = out.decode().strip()
    else:
        ancestor = base
    # O commit precisa descender da base; senao a evidencia seria amarrada a uma linha de historia
    # que nao contem o trabalho provado.
    if _git_try(["merge-base", "--is-ancestor", ancestor, resolved], root)[0] != 0:
        die("selo RECUSADO: commit %s nao descende da base %s" % (resolved[:12], ancestor[:12]), 1)
    patch = _seal_patch(root, base, resolved, excludes)
    if not patch:
        die("selo RECUSADO: o range %s..%s nao contem mudanca fora do bundle e das evidencias"
            % (base[:12], resolved[:12]), 1)
    result["commit_sha"] = resolved
    result["commit_patch_sha256"] = hashlib.sha256(patch).hexdigest()
    tmp = result_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, result_path)
    print("seal-evidence: tarefa %s selada no commit %s (patch %s)"
          % (result["task_id"], resolved[:12], result["commit_patch_sha256"][:12]))
    return 0


# ============================================================================================
# state / approve / invalidate
# ============================================================================================
def cmd_state(argv):
    if not argv:
        die("uso: sdd.py state <dir-do-prd>", 2)
    state = load_state(assert_within_project(argv[0]))
    print(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def cmd_approve(argv):
    if len(argv) < 2:
        die("uso: sdd.py approve <dir-do-prd> <prd|techspec|tasks>", 2)
    prd_dir, artifact = assert_within_project(argv[0]), argv[1]
    if artifact not in ARTIFACTS:
        die("artefato invalido: %s (use prd, techspec ou tasks)" % artifact, 2)

    paths = dict(zip(ARTIFACTS, prd_paths(prd_dir)))
    path = paths[artifact]
    if not os.path.isfile(path):
        die("%s nao existe em %s" % (os.path.basename(path), prd_dir))

    state = load_state(prd_dir)
    artifacts = state.setdefault("artifacts", {})

    # Ordem do ciclo: nunca aprovar um artefato cujo antecessor nao esta aprovado.
    order = list(ARTIFACTS)
    idx = order.index(artifact)
    for previous in order[:idx]:
        info = artifacts.get(previous) or {}
        if info.get("status") != "approved":
            die(
                "RECUSADO: '%s' nao pode ser aprovado porque '%s' nao esta aprovado.\n"
                "  A regra do ciclo e' absoluta: nunca create-tasks sem TechSpec aprovada,\n"
                "  nunca execute-task sem tasks.md aprovado." % (artifact, previous),
                3,
            )

    current = artifacts.get(artifact) or {}
    digest = sha256_file(path)
    if current.get("status") == "approved" and current.get("hash") == digest:
        die("RECUSADO: '%s' ja esta aprovado e o conteudo nao mudou. "
            "Reaprovar sem mudanca esconderia o que nao mudou." % artifact, 3)

    set_artifact(state, artifact, "approved", digest)
    record_event(state, "approved", artifact)

    # Aprovar um artefato NAO limpa o stale dos descendentes automaticamente: cada um precisa
    # ser revisto e reaprovado, senao a cadeia de confianca seria restaurada por decreto.
    print("aprovado: %s (%s)" % (artifact, digest[:16]))
    save_state(prd_dir, state)
    return 0


def cmd_assert_approved(argv):
    """Prova que o artefato e todos os predecessores continuam aprovados pelos bytes atuais."""
    if len(argv) < 2:
        die("uso: sdd.py assert-approved <dir-do-prd> <prd|techspec|tasks>", 2)
    prd_dir, artifact = prd_dir_arg(argv[0]), argv[1]
    if artifact not in ARTIFACTS:
        die("artefato invalido: %s (use prd, techspec ou tasks)" % artifact, 2)

    paths = dict(zip(ARTIFACTS, prd_paths(prd_dir)))
    state = load_state(prd_dir)
    artifacts = state.get("artifacts") or {}
    checked = []
    for name in ARTIFACTS[:ARTIFACTS.index(artifact) + 1]:
        path = paths[name]
        info = artifacts.get(name) or {}
        if not os.path.isfile(path):
            die("RECUSADO: %s nao existe em %s" % (os.path.basename(path), prd_dir), 3)
        if info.get("status") != "approved":
            die("RECUSADO: '%s' nao esta aprovado (status=%r)" % (name, info.get("status")), 3)
        expected = info.get("hash")
        actual = sha256_file(path)
        if not expected:
            die("RECUSADO: '%s' aprovado sem hash armazenado" % name, 3)
        if expected != actual:
            die(
                "RECUSADO: '%s' mudou depois da aprovacao.\n"
                "  armazenado: %s\n  atual:      %s\n"
                "  Rode invalidate --from %s, revise e aprove novamente."
                % (name, expected, actual, name),
                3,
            )
        checked.append(name)
    print("aprovacao integra: %s" % ", ".join(checked))
    return 0


def cmd_invalidate(argv):
    if len(argv) < 2:
        die("uso: sdd.py invalidate <dir-do-prd> --from <prd|techspec|tasks>", 2)
    prd_dir = prd_dir_arg(argv[0])
    if "--from" not in argv:
        die("falta --from", 2)
    artifact = argv[argv.index("--from") + 1]
    if artifact not in ARTIFACTS:
        die("artefato invalido: %s" % artifact, 2)

    state = load_state(prd_dir)
    artifacts = state.setdefault("artifacts", {})
    order = list(ARTIFACTS)
    idx = order.index(artifact)

    set_artifact(state, artifact, "draft")
    marked = [artifact]
    # Editar um artefato aprovado torna TODOS os descendentes stale. Essa e' a propagacao que
    # impede de continuar executando tarefas derivadas de um requisito que mudou.
    for descendant in order[idx + 1:]:
        # `setdefault` aqui criava registro vazio para artefato que nunca existiu, e o estado
        # passava a afirmar conhecer um `tasks` que ninguem escreveu. Descendente sem registro
        # nao tem o que invalidar.
        info = artifacts.get(descendant)
        if info and info.get("status") in ("approved", "executing", "done"):
            set_artifact(state, descendant, "stale")
            marked.append(descendant)

    record_event(state, "invalidated", artifact)
    save_state(prd_dir, state)
    print("invalidado: %s" % ", ".join(marked))
    return 0


HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")
HEX_COMMIT = re.compile(r"^[0-9a-fA-F]{40,64}$")


# Vereditos canonicos da skill review (RF-33). Um unico vocabulario para relatorio .md e JSON:
# o orchestrator usava minusculas (approved/changes_requested) no JSON e maiusculas no .md, e a
# divergencia fazia o mesmo resultado passar num validador e reprovar no outro.
REVIEW_VERDICTS = ("APPROVED", "APPROVED_WITH_REMARKS", "REJECTED", "BLOCKED")


def _verdict(value):
    return value.strip().upper() if isinstance(value, str) else ""


def _nonempty(value):
    return isinstance(value, str) and bool(value.strip())


# ============================================================================================
# Schemas versionados + validador minimo (stdlib)
# ============================================================================================
# Os contratos JSON viviam como conjuntos de campos dentro deste arquivo. Um schema em
# `config/schemas/` e' DADO: o mesmo arquivo documenta o contrato para quem le e e' o que o
# validador aplica, entao os dois nao podem divergir.
#
# POR QUE NAO `jsonschema`: o harness roda no python3 do sistema, sem pip. O subconjunto abaixo e'
# o que os schemas do harness usam. REGRA DURA: palavra-chave desconhecida FALHA a validacao.
# Um validador que ignora o que nao entende aprova por ausencia — o schema pediria `maxItems`, o
# validador pularia, e o contrato estaria escrito mas nao cobrado.
SCHEMA_ANNOTATIONS = {"$schema", "$id", "$comment", "title", "description", "default", "examples"}
SCHEMA_KEYWORDS = {
    "type", "const", "enum", "pattern", "minLength", "minimum", "minItems", "items",
    "required", "properties", "additionalProperties", "allOf", "if", "then", "else",
}


def plugin_root():
    return os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )


def load_schema(name):
    path = os.path.join(plugin_root(), "config", "schemas", name)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        # Schema ausente e' gate que nao roda: falha alto, nunca "valido".
        die("schema ilegivel ou ausente (%s): %s" % (path, exc))


def _type_ok(expected, value):
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "null":
        return value is None
    return False


def schema_errors(schema, value, where="$"):
    """Lista de erros de `value` contra `schema`. Vazia = valido."""
    errors = []
    if not isinstance(schema, dict):
        return ["%s: schema invalido (nao e' objeto)" % where]
    unknown = sorted(set(schema) - SCHEMA_KEYWORDS - SCHEMA_ANNOTATIONS)
    if unknown:
        return ["%s: palavra-chave de schema nao suportada: %s" % (where, ", ".join(unknown))]

    if "const" in schema and (value != schema["const"] or type(value) is not type(schema["const"])):
        errors.append("%s: deve ser %s" % (where, json.dumps(schema["const"])))
    if "enum" in schema and value not in schema["enum"]:
        errors.append("%s: deve ser um de %s" % (where, ", ".join(json.dumps(v) for v in schema["enum"])))
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(_type_ok(t, value) for t in types):
            return errors + ["%s: tipo esperado %s" % (where, "|".join(types))]

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append("%s: string vazia ou curta demais (min %d)" % (where, schema["minLength"]))
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append("%s: fora do formato %s" % (where, schema["pattern"]))
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append("%s: deve ser >= %s" % (where, schema["minimum"]))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append("%s: lista precisa de ao menos %d item(ns)" % (where, schema["minItems"]))
        if "items" in schema:
            for index, item in enumerate(value):
                errors.extend(schema_errors(schema["items"], item, "%s[%d]" % (where, index)))
    if isinstance(value, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append("%s: campo obrigatorio ausente: %s" % (where, key))
        if schema.get("additionalProperties") is False:
            extra = sorted(set(value) - set(props))
            if extra:
                errors.append("%s: campos desconhecidos: %s" % (where, ", ".join(extra)))
        for key, sub in props.items():
            if key in value:
                errors.extend(schema_errors(sub, value[key], "%s.%s" % (where, key)))

    for index, sub in enumerate(schema.get("allOf", [])):
        errors.extend(schema_errors(sub, value, where))
    if "if" in schema:
        branch = "then" if not schema_errors(schema["if"], value, where) else "else"
        if branch in schema:
            label = schema.get("$comment") or "regra condicional"
            errors.extend("%s [%s]" % (e, label) for e in schema_errors(schema[branch], value, where))
    return errors


def _relative_ref_error(reference):
    """Referencia de evidencia tem de ser caminho relativo, sem escapar da raiz.

    Caminho absoluto amarra a prova a uma maquina; `..` a tira do repositorio. Nos dois casos o
    auditor seguinte nao consegue reabrir o arquivo — e prova que nao se reabre nao e' prova.
    """
    path = reference.split("#", 1)[0].replace("\\", "/")
    if not path or path.startswith("/") or re.match(r"^[A-Za-z]:", path):
        return "referencia de evidencia deve ser caminho relativo: %r" % reference
    if ".." in path.split("/"):
        return "referencia de evidencia contem escape de diretorio: %r" % reference
    return None


RESULT_SCHEMAS = {
    "execution": "execution-result.schema.json",
    "review": "review-result.schema.json",
    "checkpoint": "checkpoint.schema.json",
}


def result_errors(kind, data):
    """Erros de um resultado SDD contra o schema versionado + regras de caminho."""
    if not isinstance(data, dict):
        return ["resultado deve ser objeto JSON"]
    normalized = dict(data)
    # Tolerancia herdada: o veredito ja era comparado sem caixa. O schema fala maiusculas; aqui
    # so' se normaliza a caixa, nunca o vocabulario — `changes_requested` continua invalido.
    for key in ("review_verdict", "verdict"):
        if isinstance(normalized.get(key), str):
            normalized[key] = _verdict(normalized[key])
    errors = schema_errors(load_schema(RESULT_SCHEMAS[kind]), normalized)
    refs = []
    if kind in ("execution", "review"):
        refs.extend(x for x in data.get("evidence") or [] if isinstance(x, str))
        refs.extend(c.get("evidence_ref") for c in data.get("criteria") or []
                    if isinstance(c, dict) and isinstance(c.get("evidence_ref"), str))
        if isinstance(data.get("patch_ref"), str):
            refs.append(data["patch_ref"])
    else:
        refs.extend(data[k] for k in ("report_path", "result_path") if isinstance(data.get(k), str))
    for ref in refs:
        problem = _relative_ref_error(ref)
        if problem:
            errors.append(problem)
    return errors


def cmd_validate_result(argv):
    if len(argv) < 2 or argv[0] not in RESULT_SCHEMAS:
        die("uso: sdd.py validate-result <execution|review|checkpoint> <arquivo.json> [--task-id <id>]", 2)
    kind, path = argv[0], argv[1]
    if not os.path.isfile(path):
        die("resultado nao encontrado: %s" % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        die("resultado JSON ilegivel: %s" % exc)
    if not isinstance(data, dict):
        die("resultado deve ser objeto JSON")

    errors = result_errors(kind, data)
    if "--task-id" in argv:
        expected = argv[argv.index("--task-id") + 1]
        if data.get("task_id") != expected:
            errors.append("task_id diverge: esperado %s" % expected)

    if errors:
        sys.stderr.write("[lt sdd] validate-result REJEITADO (%d erro(s)):\n" % len(errors))
        for error in errors:
            sys.stderr.write("  - %s\n" % error)
        return 1
    print("validate-result OK: %s (%s)" % (kind, RESULT_SCHEMAS[kind]))
    return 0


def cmd_runtime_capabilities(argv):
    host = "claude"
    if "--host" in argv:
        host = argv[argv.index("--host") + 1]
    if host not in ("claude", "codex", "copilot", "opencode"):
        die("host invalido: %s" % host, 2)
    capabilities = {
        "schema_version": 1,
        "host": host,
        "isolated_worktrees": False,
        "safe_concurrent_writes": False,
        "lock_strategy": "flock-or-atomic-rename",
        "cancellation_strategy": "discard-late-result",
        "ownership_validation": False,
    }
    print(json.dumps(capabilities, ensure_ascii=False, sort_keys=True))
    return 0


# ============================================================================================
# snapshot / task-patch
# ============================================================================================
# O harness nao commita (R-GOV-001). Tarefas seguidas na mesma arvore, portanto, nao podem tirar
# o patch com `git diff <commit>`: o patch da 2.0 carregaria o da 1.0. O snapshot grava a arvore
# de trabalho inteira (rastreados, modificados e nao rastreados que o .gitignore nao exclui) como
# objeto `tree`, usando um indice TEMPORARIO: nenhum commit, nenhuma ref e nenhum `git add` no
# indice real. Dois snapshots delimitam exatamente o que uma tarefa mudou.
#
# O indice temporario parte de uma COPIA do real porque `GIT_INDEX_FILE` apontando para arquivo
# vazio e' recusado ("index file smaller than expected"), e porque a copia deixa o `add -A` usar
# o cache de stat em vez de reler o repositorio inteiro.
def _git(args, env=None, cwd=None):
    proc = _subprocess.run(["git"] + args, cwd=cwd, env=env, stdout=_subprocess.PIPE,
                           stderr=_subprocess.PIPE)
    if proc.returncode != 0:
        die("git %s falhou: %s" % (" ".join(args[:2]), proc.stderr.decode("utf-8", "replace").strip()))
    return proc.stdout


def cmd_snapshot(argv):
    import shutil
    import tempfile
    root = project_root()
    real_index = _git(["rev-parse", "--git-path", "index"], cwd=root).decode().strip()
    if not os.path.isabs(real_index):
        real_index = os.path.join(root, real_index)
    tmpdir = tempfile.mkdtemp(prefix="lt-snapshot-")
    try:
        idx = os.path.join(tmpdir, "index")
        if os.path.isfile(real_index):
            shutil.copyfile(real_index, idx)
        env = dict(os.environ, GIT_INDEX_FILE=idx)
        _git(["add", "-A"], env=env, cwd=root)
        tree = _git(["write-tree"], env=env, cwd=root).decode().strip()
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print(tree)
    return 0


def cmd_task_patch(argv):
    if len(argv) < 3:
        die("uso: sdd.py task-patch <tree-antes> <tree-depois> <arquivo-patch> [--exclude <caminho>]...", 2)
    before, after, out = argv[0], argv[1], argv[2]
    excludes = [argv[i + 1] for i, a in enumerate(argv) if a == "--exclude" and i + 1 < len(argv)]
    root = project_root()
    pathspec = ["--", "."] + [":(exclude)%s" % e for e in excludes]
    patch = _git(["diff", "--binary", before, after] + pathspec, cwd=root)
    out_path = out if os.path.isabs(out) else os.path.join(root, out)
    assert_within_project(os.path.dirname(out_path) or root)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as fh:
        fh.write(patch)
    print(hashlib.sha256(patch).hexdigest())
    return 0


# ============================================================================================
# waves
# ============================================================================================
# A composicao de waves do execute-all-tasks era prosa ("alguma paralelizavel=false -> so ela,
# senao todas paralelizaveis juntas"). A coluna tem tres valores, nao dois: com `—` indefinido,
# duas leituras da mesma tasks.md davam cronogramas diferentes, e `Com X.Y` era ignorado (a
# tarefa podia cair na mesma wave de quem nao declarou). Decisao registrada:
#   - `—` e `Não` rodam sozinhas;
#   - `Com X.Y` agrupa SO com quem tambem declara a reciproca, e so entre as prontas;
#   - entre as prontas, vence o menor id; o grupo dele e' a wave.
def _resolve_bundle(slug):
    mapped = _config_spec_repos(project_root()).get(slug)
    if mapped:
        base = mapped if os.path.isabs(mapped) else os.path.join(project_root(), mapped)
        if not os.path.isdir(base):
            return None
        return os.path.join(specs_root_of(os.path.realpath(base)), "prd-%s" % slug)
    return os.path.join(specs_root(), "prd-%s" % slug)


def _external_status(dep):
    slug, tid = dep.split("/", 1)
    bundle = _resolve_bundle(slug)
    tasks = os.path.join(bundle, "tasks.md") if bundle else None
    if not tasks or not os.path.isfile(tasks):
        return None, "bundle %s nao encontrado" % slug
    for row in parse_tasks_table(tasks):
        if row["id"] == tid:
            return row["status"], None
    return None, "tarefa %s ausente em %s" % (tid, slug)


def plan_waves(rows):
    def key(tid):
        return tuple(int(x) for x in tid.split("."))

    by_id = dict((r["id"], r) for r in rows)
    done = set(r["id"] for r in rows if r["status"] == "done")
    pending = set(r["id"] for r in rows if r["status"] == "pending")
    partners = {}
    for r in rows:
        par = r["parallel"]
        partners[r["id"]] = set(p.strip() for p in par[3:].split(",")) if par.startswith("Com") else set()

    external = {}
    for r in rows:
        for dep in ([] if r["deps"] == "—" else [d.strip() for d in r["deps"].split(",")]):
            if "/" in dep and dep not in external:
                external[dep] = _external_status(dep)

    waves, blocked = [], {}
    while pending:
        ready = []
        for tid in sorted(pending, key=key):
            deps = [] if by_id[tid]["deps"] == "—" else [d.strip() for d in by_id[tid]["deps"].split(",")]
            waiting = []
            for dep in deps:
                if "/" in dep:
                    status, why = external[dep]
                    if status != "done":
                        waiting.append("%s (%s)" % (dep, why or status))
                elif dep not in done:
                    waiting.append(dep)
            if waiting:
                blocked[tid] = waiting
            else:
                blocked.pop(tid, None)
                ready.append(tid)
        if not ready:
            break
        head = ready[0]
        group = [head] + [t for t in ready[1:] if t in partners[head] and head in partners[t]]
        waves.append(group)
        done |= set(group)
        pending -= set(group)
    return waves, dict((t, blocked.get(t, ["dependencia nao concluida"])) for t in sorted(pending, key=key))


def cmd_waves(argv):
    if not argv:
        die("uso: sdd.py waves <dir-do-prd> [--next]", 2)
    prd_dir = prd_dir_arg(argv[0])
    tasks = os.path.join(prd_dir, "tasks.md")
    if not os.path.isfile(tasks):
        die("tasks.md nao encontrado em %s" % prd_dir)
    rows = parse_tasks_table(tasks)
    if not rows:
        die("nenhuma linha de tarefa reconhecida em %s" % tasks)
    waves, stuck = plan_waves(rows)
    if "--next" in argv:
        if waves:
            print(", ".join(waves[0]))
            return 0
        if stuck:
            for tid, why in stuck.items():
                sys.stderr.write("bloqueada: %s <- %s\n" % (tid, "; ".join(why)))
            return 1
        print("")
        return 0
    for i, wave in enumerate(waves, 1):
        print("wave %d: %s" % (i, ", ".join(wave)))
    for tid, why in stuck.items():
        print("bloqueada: %s <- %s" % (tid, "; ".join(why)))
    return 0


# ============================================================================================
# check-traceability
# ============================================================================================
# Cadeia requisito -> tarefa -> evidencia, nos dois sentidos:
#   - todo RF/REQ do prd.md aparece na `## Cobertura de Requisitos` do tasks.md;
#   - todo RF citado na cobertura ou numa evidencia existe no prd.md (sem orfao);
#   - toda tarefa `done` tem relatorio `<id>_execution_report.md`, criterios com `->` e linhas
#     `Requisito:` que citam os RFs que a cobertura atribui a ela.
#
# POR QUE ZERO TAREFAS DONE NAO E' FALHA AQUI: no contrato de origem, "0 tarefas verificadas" era
# gate vacuo e reprovava. Neste harness o comando tambem roda na fase de planejamento, quando
# nenhuma tarefa executou; reprovar ali ensinaria a ignorar o comando. O vacuo e' DITO na saida —
# "evidencia nao confrontada" — e nunca impresso como cadeia verificada.
RE_REQ_LINE = re.compile(r"(?im)^\s*[-*]?\s*Requisitos?\s*:\s*(.+)$")


def _section(text, title):
    lines, inside = [], False
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("## "):
            if inside:
                break
            inside = stripped[3:].strip().lower() == title.lower()
            continue
        if inside:
            lines.append(line)
    return lines


def parse_coverage(tasks_text):
    """(mapa tarefa -> RFs, RFs citados sem tarefa associada, todos os RFs da secao)."""
    mapping, loose, every = {}, set(), set()
    for line in _section(tasks_text, "Cobertura de Requisitos"):
        found = [m.group(0) for m in RE_RF.finditer(line)]
        every.update(found)
        stripped = line.strip()
        if stripped.startswith("|"):
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            task = next((c for c in cells if RE_TASK_ID.match(c)), None)
            if task and found:
                mapping.setdefault(task, [])
                mapping[task].extend(rf for rf in found if rf not in mapping[task])
                continue
        loose.update(found)
    return mapping, loose, every


def criteria_items(report_text):
    items, inside, fenced = [], False, False
    for line in report_text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        if stripped.startswith("## "):
            if inside:
                break
            inside = stripped[3:].strip() in ("Critérios de Aceite", "Criterios de Aceite")
            continue
        # Item de topo apenas: sub-item indentado e' detalhe, nao criterio.
        if inside and line.startswith("- "):
            items.append(stripped[2:])
    return items


def cmd_check_traceability(argv):
    if not argv:
        die("uso: sdd.py check-traceability <dir-do-prd>", 2)
    prd_dir = prd_dir_arg(argv[0])
    prd, _techspec, tasks = prd_paths(prd_dir)
    for required in (prd, tasks):
        if not os.path.isfile(required):
            die("%s nao encontrado em %s" % (os.path.basename(required), prd_dir), 2)
    with open(prd, "r", encoding="utf-8") as fh:
        prd_text = fh.read()
    with open(tasks, "r", encoding="utf-8") as fh:
        tasks_text = fh.read()

    requirements = []
    for m in RE_RF.finditer(prd_text):
        if m.group(0) not in requirements:
            requirements.append(m.group(0))
    known = set(requirements)
    rows = parse_tasks_table(tasks)
    statuses = dict((r["id"], r["status"]) for r in rows)
    mapping, loose, every = parse_coverage(tasks_text)
    covered = set(loose)
    for rfs in mapping.values():
        covered.update(rfs)

    gaps, notices = [], []
    for rf in requirements:
        if rf not in covered:
            gaps.append("requisito_sem_tarefa: %s — nenhuma linha de '## Cobertura de Requisitos' o cobre" % rf)
    for rf in sorted(every - known):
        gaps.append("requisito_orfao: %s citado na cobertura mas ausente do prd.md" % rf)
    for task in sorted(mapping):
        if task not in statuses:
            gaps.append("tarefa_orfa: %s aparece na cobertura mas nao na tabela de tarefas" % task)
    if mapping:
        for task in sorted(statuses):
            if task not in mapping:
                notices.append("tarefa %s sem requisito na cobertura (tarefa de suporte?)" % task)

    verified = 0
    done = [t for t in sorted(statuses) if statuses[t] == "done"]
    for task in done:
        before = len(gaps)
        report = os.path.join(prd_dir, "%s_execution_report.md" % task)
        if not os.path.isfile(report):
            gaps.append("tarefa_sem_relatorio: %s esta done sem %s" % (task, os.path.basename(report)))
            continue
        with open(report, "r", encoding="utf-8") as fh:
            text = fh.read()
        cited = []
        for line in RE_REQ_LINE.finditer(text):
            cited.extend(m.group(0) for m in RE_RF.finditer(line.group(1)))
        for rf in sorted(set(cited) - known):
            gaps.append("evidencia_orfa: %s cita %s, que nao existe no prd.md" % (task, rf))
        expected = mapping.get(task, [])
        for rf in expected:
            if rf not in cited:
                gaps.append("requisito_sem_evidencia: %s atribuido a %s, mas o relatorio nao o cita "
                            "numa linha `Requisito:`" % (rf, task))
        if not mapping and not cited:
            gaps.append("requisito_sem_evidencia: %s esta done e o relatorio nao declara `Requisito:`" % task)
        items = criteria_items(text)
        if not items:
            gaps.append("tarefa_sem_criterios: %s — '## Critérios de Aceite' ausente ou vazia" % task)
        for item in items:
            if "->" not in item or not item.split("->", 1)[1].strip():
                gaps.append("criterio_sem_evidencia: %s: %s" % (task, item[:80]))
        if len(gaps) == before:
            verified += 1

    for notice in notices:
        print("AVISO: %s" % notice)
    if gaps:
        for gap in gaps:
            print("RUPTURA: %s" % gap)
        print("%d ruptura(s); %d requisito(s), %d tarefa(s), %d done" % (len(gaps), len(requirements), len(rows), len(done)))
        return 1
    if not done:
        print("OK: requisitos e cobertura integros (%d requisito(s), %d tarefa(s)); nenhuma tarefa done — "
              "evidencia nao confrontada" % (len(requirements), len(rows)))
    else:
        print("OK: cadeia de rastreabilidade verificada — %d requisito(s), %d tarefa(s), %d done com evidencia"
              % (len(requirements), len(rows), verified))
    return 0


# ============================================================================================
# validate-bugs
# ============================================================================================
def cmd_validate_bugs(argv):
    """Valida bugs.json (interface review -> bugfix) contra o schema canonico da governanca."""
    if not argv:
        die("uso: sdd.py validate-bugs <bugs.json>", 2)
    path = argv[0]
    schema_path = os.path.join(plugin_root(), "skills", "agent-governance", "references", "bug-schema.json")
    try:
        with open(schema_path, "r", encoding="utf-8") as fh:
            schema = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        die("schema de bugs ilegivel (%s): %s" % (schema_path, exc))
    if not os.path.isfile(path):
        die("arquivo de bugs nao encontrado: %s" % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        die("bugs.json ilegivel: %s" % exc)
    errors = schema_errors(schema, data)
    if isinstance(data, list):
        seen = set()
        for index, bug in enumerate(data):
            bid = bug.get("id") if isinstance(bug, dict) else None
            if bid in seen:
                errors.append("$[%d].id: duplicado (%s) — bugfix consumiria o mesmo bug duas vezes" % (index, bid))
            seen.add(bid)
            if isinstance(bug, dict) and isinstance(bug.get("file"), str):
                problem = _relative_ref_error(bug["file"])
                if problem:
                    errors.append("$[%d].file: %s" % (index, problem))
    if errors:
        sys.stderr.write("[lt sdd] validate-bugs REJEITADO (%d erro(s)):\n" % len(errors))
        for error in errors:
            sys.stderr.write("  - %s\n" % error)
        return 1
    print("validate-bugs OK: %d bug(s) no formato canonico" % len(data))
    return 0


# ============================================================================================
# migrate-sdd / rollback-sdd / orchestrate — estado v2
# ============================================================================================
def _opt(argv, name, default=None):
    if name in argv:
        index = argv.index(name)
        if index + 1 >= len(argv):
            die("falta valor para %s" % name, 2)
        return argv[index + 1]
    return default


def _positional(argv, flags_with_value=()):
    out, skip = [], False
    for index, arg in enumerate(argv):
        if skip:
            skip = False
            continue
        if arg in flags_with_value:
            skip = True
            continue
        if arg.startswith("--"):
            continue
        out.append(arg)
    return out


def _run_id(value, what):
    if not value or not RE_RUN_ID.match(value):
        die("%s invalido: %r (use [A-Za-z0-9._-]+)" % (what, value), 2)
    return value


def cmd_migrate_sdd(argv):
    """Converte sdd-state.json v1 em v2, com backup exclusivo do arquivo anterior.

    DIFERENCA DELIBERADA DO CONTRATO DE ORIGEM: la a migracao marcava os tres artefatos como
    aprovados pelo digest atual. Aqui o status de cada artefato e' PRESERVADO: migrar formato nao
    e' aprovar conteudo, e uma migracao que aprova por decreto e' o jeito mais silencioso de
    furar o gate humano de aprovacao.
    """
    args = _positional(argv, ("--run-id",))
    if not args:
        die("uso: sdd.py migrate-sdd <dir-do-prd> [--run-id <id>] [--dry-run]", 2)
    prd_dir = prd_dir_arg(args[0])
    run_id = _run_id(_opt(argv, "--run-id") or "migrate-%s" % utc_now().replace(":", "").replace("-", ""),
                     "run_id")
    path = state_path(prd_dir)
    previous = None
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            previous = fh.read()
    current = load_state(prd_dir)
    if previous is not None and current.get("schema_version") == STATE_VERSION:
        print("migrate-sdd: estado ja esta em v2 (run_id=%s); nada a fazer" % current.get("run_id"))
        return 0

    backup_ref = ".sdd-state.%s.legacy.json" % run_id if previous is not None else ""
    state = new_state_v2(run_id)
    for name, info in sorted((current.get("artifacts") or {}).items()):
        if name not in ARTIFACTS or not isinstance(info, dict):
            continue
        status = info.get("status") if info.get("status") in STATES else "draft"
        set_artifact(state, name, status, info.get("hash"))
    state["migration"] = {"run_id": run_id, "from_version": int(current.get("schema_version", 1))
                          if previous is not None else 0, "backup_ref": backup_ref, "at": utc_now()}
    record_event(state, "migrated", "v%s -> v2" % state["migration"]["from_version"])
    errors = state_v2_errors(state)
    if errors:
        die("RECUSADO: o estado migrado seria invalido:\n  - %s" % "\n  - ".join(errors), 3)

    if "--dry-run" in argv:
        print(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True))
        print("migrate-sdd: planejada (dry-run), nada escrito")
        return 0
    if previous is not None:
        backup = os.path.join(prd_dir, backup_ref)
        try:
            # O_EXCL: backup existente nunca e' sobrescrito. Reusar run_id apagaria a unica copia
            # do estado anterior, e o rollback passaria a restaurar a coisa errada.
            fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except OSError as exc:
            die("RECUSADO: backup %s ja existe ou nao pode ser criado (%s). Use outro --run-id."
                % (backup_ref, exc), 3)
        with os.fdopen(fd, "wb") as fh:
            fh.write(previous)
    save_state(prd_dir, state)
    print("migrate-sdd: concluida run_id=%s backup=%s" % (run_id, backup_ref or "(nenhum: nao havia estado)"))
    return 0


def cmd_rollback_sdd(argv):
    """Desfaz SOMENTE o estado v2 criado pela migracao indicada."""
    args = _positional(argv, ("--run-id",))
    if not args:
        die("uso: sdd.py rollback-sdd <dir-do-prd> [--run-id <id>]", 2)
    prd_dir = prd_dir_arg(args[0])
    state = load_state(prd_dir)
    migration = state.get("migration") if state.get("schema_version") == STATE_VERSION else None
    if not os.path.isfile(state_path(prd_dir)) or not migration:
        die("RECUSADO: o estado atual nao veio de migrate-sdd; nao ha o que reverter", 3)
    wanted = _opt(argv, "--run-id")
    if wanted and wanted != migration.get("run_id"):
        die("RECUSADO: run_id %s nao criou o estado atual (criado por %s)"
            % (wanted, migration.get("run_id")), 3)
    later = [e for e in state.get("events", []) if e.get("action") != "migrated"]
    backup_ref = migration.get("backup_ref") or ""
    if backup_ref:
        backup = os.path.join(prd_dir, backup_ref)
        if not os.path.isfile(backup):
            die("RECUSADO: backup %s ausente — rollback restauraria nada" % backup_ref, 3)
        os.replace(backup, state_path(prd_dir))
    else:
        os.remove(state_path(prd_dir))
    if later:
        # Dizer o que se perde: aprovacoes feitas depois da migracao somem junto com o v2.
        print("  aviso: %d evento(s) posteriores a migracao foram descartados (%s)"
              % (len(later), ", ".join(sorted(set(e.get("action", "?") for e in later)))))
    print("rollback-sdd: estado anterior restaurado (run_id=%s)" % migration.get("run_id"))
    return 0


def cmd_orchestrate(argv):
    """Registra uma execucao recuperavel: gates de aprovacao + plano de waves, idempotente por run_id.

    NAO executa tarefas — quem executa e' `execute-all-tasks`. O que este comando garante e' que a
    execucao comeca de uma cadeia aprovada e integra, e que o plano com que ela comecou fica
    gravado: retomar o mesmo run_id devolve o MESMO plano, em vez de recalcular sobre um tasks.md
    que pode ter mudado no meio.
    """
    args = _positional(argv, ("--run-id",))
    if not args or "--run-id" not in argv:
        die("uso: sdd.py orchestrate <dir-do-prd> --run-id <id>", 2)
    prd_dir = prd_dir_arg(args[0])
    run_id = _run_id(_opt(argv, "--run-id"), "run_id")
    state = load_state(prd_dir)
    if not os.path.isfile(state_path(prd_dir)):
        die("RECUSADO: bundle sem sdd-state.json — aprove prd, techspec e tasks antes de orquestrar", 3)
    if state.get("schema_version") != STATE_VERSION:
        die("RECUSADO: sdd-state.json em v%s. Rode `lt-sdd.sh migrate-sdd %s` antes de orquestrar."
            % (state.get("schema_version", 1), prd_dir), 3)

    for run in state.get("runs", []):
        if run.get("run_id") == run_id:
            print("orchestrate: run_id=%s ja registrado em %s (idempotente); plano gravado:"
                  % (run_id, run.get("started_at")))
            for index, wave in enumerate(run.get("waves", []), 1):
                print("  wave %d: %s" % (index, ", ".join(wave)))
            return 0

    paths = dict(zip(ARTIFACTS, prd_paths(prd_dir)))
    for name in ARTIFACTS:
        info = (state.get("artifacts") or {}).get(name) or {}
        if not os.path.isfile(paths[name]):
            die("orquestracao bloqueada: %s ausente" % os.path.basename(paths[name]), 3)
        if info.get("status") != "approved" or info.get("hash") != sha256_file(paths[name]):
            die("orquestracao bloqueada: '%s' nao esta aprovado pelos bytes atuais" % name, 3)

    rows = parse_tasks_table(paths["tasks"])
    if not rows:
        die("orquestracao bloqueada: nenhuma linha de tarefa em tasks.md", 3)
    waves, stuck = plan_waves(rows)
    state.setdefault("runs", []).append({
        "run_id": run_id,
        "started_at": utc_now(),
        "waves": waves,
        "blocked": dict((tid, why) for tid, why in stuck.items()),
        "tasks_sha256": sha256_file(paths["tasks"]),
    })
    record_event(state, "orchestrated", run_id)
    save_state(prd_dir, state)
    print("orchestrate: run_id=%s registrado com %d wave(s)" % (run_id, len(waves)))
    for index, wave in enumerate(waves, 1):
        print("  wave %d: %s" % (index, ", ".join(wave)))
    for tid, why in stuck.items():
        print("  bloqueada: %s <- %s" % (tid, "; ".join(why)))
    return 0


# ============================================================================================
# memory — memoria duravel por PRD
# ============================================================================================
# Fatos que precisam sobreviver ao contexto de uma sessao (decisao tomada, armadilha descoberta,
# comando que funciona) vivem em `<dir-do-prd>/memory/facts.jsonl`, junto da spec a que pertencem.
#
# APPEND-ONLY. Nenhuma linha e' reescrita: corrigir um fato e' gravar outro com a mesma chave. A
# versao ativa e' a ultima; as anteriores continuam la, com origem, para quem precisar entender
# por que a decisao mudou. Memoria que se reescreve apaga a propria trilha.
#
# REDACAO ANTES DE GRAVAR. O conteudo passa pelos mesmos padroes de `config/secret-patterns.json`
# que o hook de escrita usa: a memoria e' versionada junto com a spec, e um segredo gravado ali
# vira segredo commitado.
RE_MEMORY_KEY = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
MEMORY_MAX_CHARS = 4000


def redact(text):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import secret_scan  # noqa: E402
    try:
        config = secret_scan.load_config(plugin_root())
    except (IOError, OSError, ValueError) as exc:
        # Sem padroes nao ha como provar que o texto esta limpo: recusa gravar.
        die("RECUSADO: padroes de segredo ilegiveis (%s); memoria nao gravada sem redacao" % exc)
    count = 0
    for pattern in config.get("patterns", []):
        try:
            compiled = re.compile(pattern.get("regex") or "(?!)")
        except re.error:
            die("RECUSADO: padrao de segredo invalido (%s); memoria nao gravada" % pattern.get("id"))
        text, hits = compiled.subn("[REDACTED:%s]" % pattern.get("id", "secret"), text)
        count += hits
    return text, count


def memory_file(prd_dir):
    return os.path.join(prd_dir, "memory", "facts.jsonl")


def memory_entries(prd_dir):
    path = memory_file(prd_dir)
    entries = []
    if not os.path.isfile(path):
        return entries
    with open(path, "r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                sys.stderr.write("[lt sdd] memory: linha %d ilegivel ignorada\n" % lineno)
                continue
            if isinstance(entry, dict) and entry.get("key"):
                entries.append(entry)
    return entries


def cmd_memory(argv):
    usage = ("uso: sdd.py memory <dir-do-prd> add <chave> <texto...> [--task <id>] [--session <id>]\n"
             "     sdd.py memory <dir-do-prd> list\n"
             "     sdd.py memory <dir-do-prd> show <chave>")
    flags = ("--task", "--session")
    args = _positional(argv, flags)
    if len(args) < 2 or args[1] not in ("add", "list", "show"):
        die(usage, 2)
    prd_dir, action = prd_dir_arg(args[0]), args[1]
    if not os.path.isdir(prd_dir):
        die("bundle inexistente: %s" % prd_dir, 3)

    if action == "add":
        if len(args) < 4:
            die(usage, 2)
        key = args[2]
        if not RE_MEMORY_KEY.match(key):
            die("chave invalida: %r (use [a-z0-9._-], ate 64)" % key, 2)
        content = " ".join(args[3:]).strip()
        if not content:
            die("texto vazio", 2)
        if len(content) > MEMORY_MAX_CHARS:
            die("texto com %d caracteres (max %d): memoria e' fato curto, nao log" % (len(content), MEMORY_MAX_CHARS), 2)
        content, redactions = redact(content)
        task = _opt(argv, "--task", "")
        if task and not RE_TASK_ID.match(task):
            die("--task invalido: %r" % task, 2)
        previous = [e for e in memory_entries(prd_dir) if e["key"] == key]
        entry = {
            "ts": utc_now(), "key": key, "content": content,
            "task": task, "session": _opt(argv, "--session", os.environ.get("CLAUDE_SESSION_ID", "")),
            "redactions": redactions, "supersedes": len(previous),
        }
        os.makedirs(os.path.dirname(memory_file(prd_dir)), exist_ok=True)
        # Uma unica escrita com O_APPEND: linha curta nao intercala com outra escrita concorrente.
        fd = os.open(memory_file(prd_dir), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        with os.fdopen(fd, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
        note = " (%d trecho(s) redigido(s))" % redactions if redactions else ""
        if previous and previous[-1].get("content") != content:
            note += " — substitui a versao anterior"
        print("memory: fato '%s' gravado%s" % (key, note))
        return 0

    entries = memory_entries(prd_dir)
    if action == "list":
        active = {}
        versions = {}
        for entry in entries:
            active[entry["key"]] = entry
            versions[entry["key"]] = versions.get(entry["key"], 0) + 1
        if not active:
            print("memory: nenhum fato em %s" % os.path.relpath(memory_file(prd_dir)))
            return 0
        for key in sorted(active):
            entry = active[key]
            origin = "tarefa %s" % entry["task"] if entry.get("task") else "bundle"
            extra = " [%d versoes]" % versions[key] if versions[key] > 1 else ""
            print("- %s (%s, %s)%s: %s" % (key, origin, entry.get("ts", "?"), extra, entry.get("content", "")))
        return 0

    if len(args) < 3:
        die(usage, 2)
    history = [e for e in entries if e["key"] == args[2]]
    if not history:
        die("memory: chave '%s' nao encontrada" % args[2], 1)
    for index, entry in enumerate(history, 1):
        state = "ativa" if index == len(history) else "substituida"
        print("v%d [%s] %s sessao=%s tarefa=%s redacoes=%s" % (
            index, state, entry.get("ts", "?"), entry.get("session") or "-",
            entry.get("task") or "-", entry.get("redactions", 0)))
        print("   %s" % entry.get("content", ""))
    return 0


# ============================================================================================
# telemetry / metrics — leitura dos logs LOCAIS que os hooks ja escrevem
# ============================================================================================
# Fontes (nenhuma remota):
#   <LT_HOME>/telemetry.jsonl (+ rotacoes .gz)  — post-skill-fire.sh: disparo de skill
#   <LT_HOME>/cost-daily.jsonl                  — post-tool-capture-tokens.sh: tokens por mensagem
#   <projeto>/.lt/audit/hook-fires.log          — lt_audit_fire: decisoes dos hooks
#   <LT_HOME>/approve.log                       — approve.sh: aprovacoes
# LT_HOME = $LT_HOME, senao $CLAUDE_CONFIG_DIR/lt, senao ~/.claude/lt — a mesma cascata dos hooks.
#
# AUSENTE NAO E' ZERO. Log inexistente e' dito como tal ("sem dados"), nunca impresso como
# "0 disparos", que leria como uso nulo medido.
def lt_home():
    if os.environ.get("LT_HOME"):
        return os.environ["LT_HOME"]
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(cfg, "lt")


def _jsonl(paths):
    import glob
    import gzip
    rows, bad = [], 0
    for pattern in paths:
        for path in sorted(glob.glob(pattern)):
            opener = gzip.open if path.endswith(".gz") else open
            try:
                with opener(path, "rt", encoding="utf-8") as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            row = json.loads(line)
                        except ValueError:
                            bad += 1
                            continue
                        if isinstance(row, dict):
                            rows.append(row)
            except (IOError, OSError):
                bad += 1
    return rows, bad


def _since_days(argv, default=7):
    raw = _opt(argv, "--since", str(default))
    match = re.match(r"^(\d+)d?$", raw)
    if not match:
        die("--since invalido: %r (use N ou Nd, em dias)" % raw, 2)
    return int(match.group(1))


def _in_window(row, days):
    import datetime
    day = row.get("day") or str(row.get("ts", ""))[:10]
    try:
        when = datetime.datetime.strptime(day, "%Y-%m-%d").date()
    except ValueError:
        return False, None
    today = datetime.datetime.now(datetime.timezone.utc).date()
    return (today - when).days < days if days > 0 else True, when


TOKEN_FIELDS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")


def telemetry_data(days):
    home = lt_home()
    skills, bad_s = _jsonl([os.path.join(home, "telemetry.jsonl"), os.path.join(home, "telemetry.jsonl.*.gz")])
    costs, bad_c = _jsonl([os.path.join(home, "cost-daily.jsonl")])
    data = {"period_days": days, "lt_home": home, "malformed_lines": bad_s + bad_c,
            "skill_log_present": os.path.isfile(os.path.join(home, "telemetry.jsonl")),
            "cost_log_present": os.path.isfile(os.path.join(home, "cost-daily.jsonl"))}
    counts, sessions, weeks = {}, set(), {}
    for row in skills:
        inside, when = _in_window(row, days)
        if row.get("kind") != "skill.fire" or not row.get("skill"):
            continue
        if when is not None:
            week = "%d-W%02d" % when.isocalendar()[:2]
            weeks.setdefault(week, {"skill_fires": 0, "tokens": 0})["skill_fires"] += 1
        if not inside:
            continue
        counts[row["skill"]] = counts.get(row["skill"], 0) + 1
        if row.get("session"):
            sessions.add(row["session"])
    total = sum(counts.values())
    data["skill_fires"] = total
    data["sessions"] = len(sessions)
    data["top_skills"] = [{"skill": k, "count": v, "pct": round(100.0 * v / total, 1)}
                          for k, v in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:5]]
    tokens = dict((f, 0) for f in TOKEN_FIELDS)
    per_day, per_model = {}, {}
    for row in costs:
        inside, when = _in_window(row, days)
        amount = sum(int(row.get(f) or 0) for f in TOKEN_FIELDS)
        if when is not None:
            week = "%d-W%02d" % when.isocalendar()[:2]
            weeks.setdefault(week, {"skill_fires": 0, "tokens": 0})["tokens"] += amount
        if not inside:
            continue
        for f in TOKEN_FIELDS:
            tokens[f] += int(row.get(f) or 0)
        day = str(when)
        per_day[day] = per_day.get(day, 0) + amount
        model = row.get("model") or "?"
        per_model[model] = per_model.get(model, 0) + amount
    data["tokens"] = tokens
    data["tokens_total"] = sum(tokens.values())
    read = tokens["cache_read_input_tokens"]
    fresh = tokens["input_tokens"] + tokens["cache_creation_input_tokens"]
    data["cache_hit_ratio"] = round(read / float(read + fresh), 3) if read + fresh else None
    data["tokens_per_day"] = dict(sorted(per_day.items()))
    data["tokens_per_model"] = dict(sorted(per_model.items(), key=lambda kv: -kv[1]))
    data["trend"] = [{"week": w, **weeks[w]} for w in sorted(weeks)[-4:]]
    return data


def cmd_telemetry(argv):
    if not argv or argv[0] != "report":
        die("uso: sdd.py telemetry report [--since N] [--budget <tokens/dia>] [--json]", 2)
    days = _since_days(argv)
    budget = _opt(argv, "--budget")
    if budget is not None and not re.match(r"^\d+$", budget):
        die("--budget invalido: %r (inteiro, tokens por dia)" % budget, 2)
    data = telemetry_data(days)
    over = []
    if budget is not None:
        over = [(d, t) for d, t in data["tokens_per_day"].items() if t > int(budget)]
        data["budget"] = {"tokens_per_day": int(budget), "days_over": [d for d, _ in over]}
    if "--json" in argv:
        print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print("Relatorio de telemetria local (ultimos %d dia(s)) — %s" % (days, data["lt_home"]))
        if not data["skill_log_present"]:
            print("  skills: sem dados (telemetry.jsonl ausente — nao e' o mesmo que zero uso)")
        else:
            print("  disparos de skill: %d em %d sessao(oes)" % (data["skill_fires"], data["sessions"]))
            for index, item in enumerate(data["top_skills"], 1):
                print("    %d. %-34s %4d  (%.1f%%)" % (index, item["skill"], item["count"], item["pct"]))
        if not data["cost_log_present"]:
            print("  tokens: sem dados (cost-daily.jsonl ausente)")
        else:
            print("  tokens: %d total (input %d, output %d, cache read %d, cache write %d)" % (
                data["tokens_total"], data["tokens"]["input_tokens"], data["tokens"]["output_tokens"],
                data["tokens"]["cache_read_input_tokens"], data["tokens"]["cache_creation_input_tokens"]))
            if data["cache_hit_ratio"] is not None:
                print("  cache hit: %.1f%%" % (100 * data["cache_hit_ratio"]))
        if data["trend"]:
            print("  tendencia semanal:")
            for week in data["trend"]:
                print("    %s  skills=%-5d tokens=%d" % (week["week"], week["skill_fires"], week["tokens"]))
        if data["malformed_lines"]:
            print("  aviso: %d linha(s) malformada(s) ignorada(s)" % data["malformed_lines"])
        if budget is not None:
            if over:
                for day, amount in over:
                    print("  ORCAMENTO ESTOURADO: %s com %d tokens (limite %s/dia)" % (day, amount, budget))
            else:
                print("  orcamento: nenhum dia acima de %s tokens" % budget)
    return 1 if over else 0


def cmd_metrics(argv):
    """Metricas operacionais: decisoes de hook, aprovacoes, tokens e custo estatico das skills."""
    days = _since_days(argv, 30)
    project = project_root()
    fires = {}
    log = os.path.join(project, ".lt", "audit", "hook-fires.log")
    present = os.path.isfile(log)
    if present:
        with open(log, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = [p.strip() for p in line.split("|")]
                if len(parts) < 3 or not parts[1].startswith("hook="):
                    continue
                inside, _ = _in_window({"ts": parts[0]}, days)
                if not inside:
                    continue
                key = (parts[1][5:], parts[2].replace("status=", ""))
                fires[key] = fires.get(key, 0) + 1
    approvals = {}
    approve_log = os.path.join(lt_home(), "approve.log")
    if os.path.isfile(approve_log):
        import time
        floor = time.time() - days * 86400
        with open(approve_log, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                cells = line.rstrip("\n").split("\t")
                if len(cells) >= 2 and cells[0].isdigit() and int(cells[0]) >= floor:
                    approvals[cells[1]] = approvals.get(cells[1], 0) + 1
    # Custo ESTATICO de contexto: chars/3.5 por SKILL.md, a mesma heuristica do harness de origem.
    # E' estimativa, e diz que e': serve para comparar skills entre si, nao para faturar.
    static = []
    skills_dir = os.path.join(plugin_root(), "skills")
    for name in sorted(os.listdir(skills_dir)) if os.path.isdir(skills_dir) else []:
        path = os.path.join(skills_dir, name, "SKILL.md")
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as fh:
                static.append({"skill": name, "est_tokens": int(len(fh.read()) / 3.5)})
    data = {
        "period_days": days,
        "hook_log_present": present,
        "hook_decisions": [{"hook": h, "status": st, "count": c} for (h, st), c in sorted(fires.items())],
        "approvals": dict(sorted(approvals.items())),
        "tokens_total": telemetry_data(days)["tokens_total"],
        "skill_context_tokens": sorted(static, key=lambda x: -x["est_tokens"]),
    }
    if "--json" in argv:
        print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    print("Metricas (ultimos %d dia(s))" % days)
    if not present:
        print("  hooks: sem dados (%s ausente)" % os.path.relpath(log, project))
    else:
        print("  decisoes de hook:")
        for item in data["hook_decisions"] or [{"hook": "(nenhuma no periodo)", "status": "", "count": 0}]:
            print("    %-38s %-20s %d" % (item["hook"], item["status"], item["count"]))
    print("  aprovacoes: %s" % (", ".join("%s=%d" % kv for kv in data["approvals"].items()) or "nenhuma no periodo"))
    print("  tokens no periodo: %d" % data["tokens_total"])
    print("  contexto estatico por skill (estimativa chars/3.5):")
    for item in data["skill_context_tokens"][:12]:
        print("    %-34s ~%d tok" % (item["skill"], item["est_tokens"]))
    return 0


# ============================================================================================
# session-audit — o que o Stop hook consulta
# ============================================================================================
def cmd_session_audit(argv):
    """Tarefas em andamento ou concluidas sem relatorio/evidencia, em todos os bundles do repo.

    Consultivo: sai 0 mesmo com achados (o hook de Stop avisa, nao prende a sessao). `--strict`
    sai 1 com achados, para uso em CI.
    """
    import glob
    findings = []
    root = specs_root()
    for tasks in sorted(glob.glob(os.path.join(root, "prd-*", "tasks.md"))):
        bundle = os.path.dirname(tasks)
        rel = os.path.relpath(bundle, project_root())
        for row in parse_tasks_table(tasks):
            if row["status"] not in ("in_progress", "done"):
                continue
            report = os.path.join(bundle, "%s_execution_report.md" % row["id"])
            if not os.path.isfile(report):
                findings.append("%s: tarefa %s (%s) sem %s" % (rel, row["id"], row["status"], os.path.basename(report)))
                continue
            if row["status"] != "done":
                continue
            with open(report, "r", encoding="utf-8", errors="replace") as fh:
                match = RE_RESULT_PATH.search(fh.read())
            if not match:
                findings.append("%s: tarefa %s done sem `result_path=` no relatorio" % (rel, row["id"]))
                continue
            ref = match.group(1).split("#", 1)[0]
            target = ref if os.path.isabs(ref) else os.path.join(project_root(), ref)
            if not os.path.isfile(target):
                findings.append("%s: tarefa %s done com result_path inexistente (%s)" % (rel, row["id"], ref))
    for finding in findings:
        print(finding)
    return 1 if findings and "--strict" in argv else 0


COMMANDS = {
    "hash": cmd_hash,
    "sync-spec-hash": cmd_sync_spec_hash,
    "check-spec-drift": cmd_check_spec_drift,
    "validate-sdd": cmd_validate_sdd,
    "seal-evidence": cmd_seal_evidence,
    "state": cmd_state,
    "specs-root": cmd_specs_root,
    "skills-available": cmd_skills_available,
    "approve": cmd_approve,
    "assert-approved": cmd_assert_approved,
    "invalidate": cmd_invalidate,
    "validate-result": cmd_validate_result,
    "runtime-capabilities": cmd_runtime_capabilities,
    "snapshot": cmd_snapshot,
    "task-patch": cmd_task_patch,
    "waves": cmd_waves,
    "migrate-sdd": cmd_migrate_sdd,
    "rollback-sdd": cmd_rollback_sdd,
    "orchestrate": cmd_orchestrate,
    "check-traceability": cmd_check_traceability,
    "validate-bugs": cmd_validate_bugs,
    "memory": cmd_memory,
    "telemetry": cmd_telemetry,
    "metrics": cmd_metrics,
    "session-audit": cmd_session_audit,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.stderr.write("uso: sdd.py <%s> [args]\n" % "|".join(sorted(COMMANDS)))
        return 2
    cmd = sys.argv[1]
    if cmd not in COMMANDS:
        die("subcomando desconhecido: %s" % cmd, 2)
    return COMMANDS[cmd](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
