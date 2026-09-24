#!/usr/bin/env python3
"""Gate de release sobre as evals do plugin: a eval deixa de ser relatorio e passa a bloquear.

Dois modos, porque a eval custa dinheiro e o release nao pode depender de credencial no CI:

  eval-gate.py check <report.json> [--write]
      Julga um relatorio do `claude plugin eval` contra os limites abaixo. Com --write e tudo
      aprovado, grava docs/benchmarks/eval-baseline.json carimbado com o digest do conteudo
      avaliado. Roda no workflow pago (plugin-eval.yml) e na maquina de quem mede.

  eval-gate.py fresh
      GRATIS, roda no release: a linha de base aprovada tem de ter sido medida sobre o conteudo
      que esta sendo publicado (digest de skills/agents/commands/evals) e ter passado no gate.
      Skill editada depois da ultima eval = release bloqueado ate' medir de novo.

LIMITES (cada um nasceu de um defeito medido, nao de gosto):
  - juiz com acuracia >= 0.90 na calibracao (docs/benchmarks/judge-calibration.json): o haiku
    mediu 0.73 e reprovava respostas corretas; gate com regua ruim bloqueia por erro do juiz;
  - >= 3 execucoes por caso: com 2, uma unica execucao ruim mexia 0.1 na nota da skill;
  - roteamento: positivos >= 95% disparam a skill, negativos 100% ficam calados;
  - nenhuma skill cai mais de 0.05 contra a linha de base aprovada (regressao);
  - toda skill com ganho >= 0 sobre o modelo SEM o plugin: skill que piora o modelo nao e' produto.
"""
import datetime
import hashlib
import json
import os
import statistics
import sys

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PLUGIN = os.path.join(REPO, "plugins", "lt")
BASELINE = os.path.join(REPO, "docs", "benchmarks", "eval-baseline.json")
CALIBRATION = os.path.join(REPO, "docs", "benchmarks", "judge-calibration.json")

MIN_JUDGE_ACCURACY = 0.90
MIN_RUNS = 3
MIN_POSITIVE_ROUTING = 0.95
MAX_REGRESSION = 0.05
MIN_DELTA = 0.0
# O que a eval mede: mexer em qualquer um destes invalida a medicao anterior.
DIGEST_PARTS = ("skills", "agents", "commands", "evals")


def content_digest():
    value = hashlib.sha256()
    for part in DIGEST_PARTS:
        root = os.path.join(PLUGIN, part)
        for current, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in ("results", "__pycache__"))
            for name in sorted(files):
                if name.endswith((".pyc", ".pyo")) or name == ".DS_Store":
                    continue
                path = os.path.join(current, name)
                value.update(os.path.relpath(path, PLUGIN).encode("utf-8") + b"\0")
                with open(path, "rb") as stream:
                    value.update(hashlib.sha256(stream.read()).digest())
    return value.hexdigest()


def load(path):
    with open(path, "r", encoding="utf-8") as stream:
        return json.load(stream)


def summarize(report):
    per_skill = {}
    cases = []
    positives = [0, 0]
    negatives = [0, 0]
    runs_seen = []
    for case in report.get("cases", []):
        arms = case.get("arms", {})
        with_runs = arms.get("with", [])
        without_runs = arms.get("without", [])
        runs_seen.append(len(with_runs))
        negative = "negativo" in case["name"]
        fired = [g.get("passed") for r in with_runs for g in r.get("graders", [])
                 if g.get("name", "").startswith("00-roteamento")]
        bucket = negatives if negative else positives
        bucket[0] += sum(1 for f in fired if f)
        bucket[1] += len(fired)
        w = statistics.mean([r.get("score", 0) for r in with_runs]) if with_runs else 0.0
        wo = statistics.mean([r.get("score", 0) for r in without_runs]) if without_runs else None
        skill = case["name"].split("--")[0]
        entry = per_skill.setdefault(skill, {"with": [], "without": []})
        entry["with"].append(w)
        if wo is not None:
            entry["without"].append(wo)
        cases.append({"case": case["name"], "with": round(w, 3),
                      "without": None if wo is None else round(wo, 3),
                      "routing_ok": "%d/%d" % (sum(1 for f in fired if f), len(fired)),
                      "negative": negative})
    skills = {}
    for skill, entry in sorted(per_skill.items()):
        w = statistics.mean(entry["with"])
        wo = statistics.mean(entry["without"]) if entry["without"] else None
        skills[skill] = {"with": round(w, 3), "without": None if wo is None else round(wo, 3),
                         "delta": None if wo is None else round(w - wo, 3)}
    return {"per_skill": skills, "cases": cases, "positives": positives, "negatives": negatives,
            "min_runs": min(runs_seen) if runs_seen else 0}


def check(report_path, write):
    report = load(report_path)
    summary = summarize(report)
    failures = []
    notes = []

    judge = (report.get("suite") or {}).get("judgeModel") or os.environ.get("LT_EVAL_JUDGE") or ""
    calibration = load(CALIBRATION) if os.path.isfile(CALIBRATION) else {}
    accuracy = (calibration.get("judges") or {}).get(judge, {}).get("accuracy")
    if not judge:
        failures.append("juiz nao identificado no relatorio; exporte LT_EVAL_JUDGE=<modelo> usado em --judge-model")
    elif accuracy is None:
        failures.append("juiz '%s' sem calibracao registrada em %s" % (judge, os.path.relpath(CALIBRATION, REPO)))
    elif accuracy < MIN_JUDGE_ACCURACY:
        failures.append("juiz '%s' com acuracia %.2f < %.2f na calibracao" % (judge, accuracy, MIN_JUDGE_ACCURACY))
    else:
        notes.append("juiz '%s' calibrado (acuracia %.2f)" % (judge, accuracy))

    if report.get("partial"):
        failures.append("relatorio parcial (%s): gate so' julga execucao completa" % report.get("partialReason"))
    if summary["min_runs"] < MIN_RUNS:
        failures.append("%d execucao(oes) por caso; o minimo e' %d" % (summary["min_runs"], MIN_RUNS))

    fired, total = summary["positives"]
    if total and fired / float(total) < MIN_POSITIVE_ROUTING:
        failures.append("roteamento positivo %d/%d < %.0f%%" % (fired, total, MIN_POSITIVE_ROUTING * 100))
    silent, total_neg = summary["negatives"]
    if silent != total_neg:
        failures.append("roteamento negativo %d/%d: skill disparou onde nao devia" % (silent, total_neg))

    baseline = load(BASELINE) if os.path.isfile(BASELINE) else {}
    # Regressao so' se compara na MESMA regua: nota com haiku contra nota com sonnet mede a troca de
    # juiz, nao a skill. Com juiz diferente, a nova medicao vira a primeira linha de base da regua.
    same_judge = baseline.get("judge_model") == judge and baseline.get("gate") == "passed"
    if baseline and not same_judge:
        notes.append("linha de base anterior em outra regua (juiz %r); regressao nao comparada"
                     % baseline.get("judge_model"))
    for skill, now in summary["per_skill"].items():
        before = (baseline.get("per_skill") or {}).get(skill, {}).get("with") if same_judge else None
        if before is not None and now["with"] < before - MAX_REGRESSION:
            failures.append("%s regrediu: %.3f -> %.3f (tolerancia %.2f)" % (skill, before, now["with"], MAX_REGRESSION))
        if now["delta"] is not None and now["delta"] < MIN_DELTA:
            failures.append("%s piora o modelo: com %.3f < sem %.3f" % (skill, now["with"], now["without"]))

    for note in notes:
        print("ok: " + note)
    for skill, now in summary["per_skill"].items():
        print("  %-32s com %.3f  sem %s  delta %s" % (skill, now["with"], now["without"], now["delta"]))
    print("  roteamento: positivos %d/%d · negativos calados %d/%d"
          % (summary["positives"][0], summary["positives"][1], summary["negatives"][0], summary["negatives"][1]))
    if failures:
        for failure in failures:
            print("FALHA: " + failure)
        print("EVAL GATE REPROVADO")
        return 1

    if write:
        aggregates = report.get("aggregates", {})
        stamped = {
            "_measured_at": datetime.date.today().isoformat(),
            "_cli": report.get("claudeVersion"),
            "_note": "Gravado por scripts/lib/eval-gate.py check --write so' com o gate aprovado.",
            "gate": "passed",
            "content_digest": content_digest(),
            "judge_model": judge, "judge_accuracy": accuracy,
            "runs_per_case": summary["min_runs"],
            "cost_usd": round(report.get("costUsd", 0), 2),
            "overall_score": round(aggregates.get("overallScore", 0), 3),
            "overall_pass_rate": round(aggregates.get("overallPassRate", 0), 3),
            "mean_delta_with_vs_without": round(aggregates.get("meanDelta", 0), 3),
            "routing": {"positives_fired": summary["positives"], "negatives_silent": summary["negatives"]},
            "per_skill": summary["per_skill"], "cases": summary["cases"],
            "history": ([{k: baseline.get(k) for k in ("_measured_at", "version", "judge_model", "overall_score",
                                                       "mean_delta_with_vs_without", "routing", "per_skill")}]
                        + baseline.get("history", []))[:10] if baseline else [],
        }
        with open(BASELINE, "w", encoding="utf-8") as stream:
            json.dump(stamped, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print("linha de base gravada: %s" % os.path.relpath(BASELINE, REPO))
    print("EVAL GATE APROVADO")
    return 0


def merge(paths, out):
    """Junta relatorios da MESMA configuracao (juiz, ablacao, versao do CLI): casos do relatorio
    posterior substituem os do anterior pelo nome. Serve para completar uma execucao que bateu o
    teto de custo sem pagar de novo pelos casos que ja fecharam. Configuracao diferente e' recusada:
    juntar reguas diferentes produziria uma nota que nenhuma execucao mediu."""
    reports = [load(path) for path in paths]
    keys = ("judgeModel", "ablation", "modelOverride")
    base = reports[0]
    for other in reports[1:]:
        for key in keys:
            if (base.get("suite") or {}).get(key) != (other.get("suite") or {}).get(key):
                print("FALHA: configuracao divergente em '%s'; merge recusado" % key)
                return 1
        if base.get("claudeVersion") != other.get("claudeVersion"):
            print("FALHA: versoes de CLI divergentes (%s x %s); merge recusado"
                  % (base.get("claudeVersion"), other.get("claudeVersion")))
            return 1
    cases = {}
    for report in reports:
        for case in report.get("cases", []):
            cases[case["name"]] = case
    merged = dict(base)
    merged["cases"] = [cases[name] for name in sorted(cases)]
    merged["costUsd"] = sum(r.get("costUsd", 0) for r in reports)

    def complete(case):
        arms = case.get("arms", {})
        return all(len([r for r in arms.get(arm, []) if not r.get("error") and not r.get("skippedPaidGraders")])
                   >= MIN_RUNS for arm in ("with", "without") if arm in arms)
    incomplete = [c["name"] for c in merged["cases"] if not complete(c)]
    merged["partial"] = bool(incomplete)
    merged["partialReason"] = ("casos incompletos: " + ", ".join(incomplete)) if incomplete else None
    scores = [r.get("score", 0) for c in merged["cases"] for r in c.get("arms", {}).get("with", [])]
    deltas = []
    for c in merged["cases"]:
        arms = c.get("arms", {})
        if arms.get("with") and arms.get("without"):
            deltas.append(statistics.mean(r.get("score", 0) for r in arms["with"])
                          - statistics.mean(r.get("score", 0) for r in arms["without"]))
    merged["aggregates"] = dict(base.get("aggregates", {}),
                                casesTotal=len(merged["cases"]),
                                overallScore=statistics.mean(scores) if scores else 0,
                                meanDelta=statistics.mean(deltas) if deltas else 0)
    with open(out, "w", encoding="utf-8") as stream:
        json.dump(merged, stream, ensure_ascii=False)
    print("merge: %d casos, custo USD %.2f, %s" % (len(merged["cases"]), merged["costUsd"],
                                                    "COMPLETO" if not incomplete else "INCOMPLETO: " + ", ".join(incomplete)))
    return 0 if not incomplete else 1


def fresh():
    if not os.path.isfile(BASELINE):
        print("FALHA: %s ausente — rode a eval e o gate antes de publicar" % os.path.relpath(BASELINE, REPO))
        return 1
    baseline = load(BASELINE)
    problems = []
    if baseline.get("gate") != "passed":
        problems.append("a linha de base nao passou no gate (gate=%r)" % baseline.get("gate"))
    if baseline.get("content_digest") != content_digest():
        problems.append("skills/agents/commands/evals mudaram depois da ultima eval aprovada")
    if problems:
        for problem in problems:
            print("FALHA: " + problem)
        print("  Meca de novo: claude plugin eval plugins/lt --judge-model <calibrado> --runs 3 "
              "--ablation with-without --json <r.json>; depois python3 scripts/lib/eval-gate.py check <r.json> --write")
        print("EVAL DESATUALIZADA")
        return 1
    print("EVAL EM DIA: linha de base aprovada (%s, juiz %s) corresponde ao conteudo publicado"
          % (baseline.get("_measured_at"), baseline.get("judge_model")))
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "check":
        return check(sys.argv[2], "--write" in sys.argv)
    if len(sys.argv) == 2 and sys.argv[1] == "fresh":
        return fresh()
    if len(sys.argv) >= 5 and sys.argv[1] == "merge" and "-o" in sys.argv:
        out = sys.argv[sys.argv.index("-o") + 1]
        inputs = [a for a in sys.argv[2:sys.argv.index("-o")]]
        return merge(inputs, out)
    if len(sys.argv) == 2 and sys.argv[1] == "digest":
        print(content_digest())
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
