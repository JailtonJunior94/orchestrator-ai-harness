#!/usr/bin/env python3
# lt / lib / shell_text.py
#
# Separa, numa linha de comando de shell, o que sera EXECUTADO do que e' apenas DADO.
#
# POR QUE ESTE ARQUIVO EXISTE — descoberto do jeito mais direto possivel
# O guarda destrutivo casava os literais em qualquer lugar do texto do comando. Resultado: ele
# bloqueou a propria sessao que estava escrevendo o teste dele, porque o teste MENCIONAVA os
# comandos como dado. Um `grep -n "rm -rf /" README.md` era tratado como se fosse `rm -rf /`.
#
# Isso nao e' um detalhe de precisao. Sobre-bloquear trabalho legitimo e' o caminho mais curto
# para a pessoa desativar o hook, e junto vai a protecao contra o comando de verdade. Ao mesmo
# tempo, sub-detectar e' vazamento: `bash -c "rm -rf /"` EXECUTA, e tem de ser pego.
#
# A REGRA
#   Conteudo entre aspas e' DADO, exceto quando o shell vai executa-lo:
#     - imediatamente apos `-c` (bash -c, sh -c, zsh -c, ssh host -c...)
#     - imediatamente apos `eval`
#     - corpo de heredoc alimentado a um interpretador (bash <<EOF, sh <<EOF)
#   Substituicao de comando — $(...) e crases — e' SEMPRE executada.
#
# LIMITE HONESTO: isto e' um separador lexico, nao um parser de shell. Nao resolve expansao de
# variavel (`CMD="rm -rf /"; $CMD`), nem ofuscacao deliberada. Para o caso adversarial existe o
# gate de aprovacao humana; este modulo serve para nao transformar trabalho comum em atrito.

import re

# Tokens apos os quais o proximo argumento entre aspas e' CODIGO, nao dado.
EXEC_AFTER = ("-c", "eval", "--command")
SHELLS = ("bash", "sh", "zsh", "ksh", "dash", "python", "python3", "node", "perl", "ruby")


def _spans(command):
    """Percorre a string uma vez devolvendo (inicio, fim, tipo, conteudo).

    tipo: 'quoted' (aspas simples ou duplas) | 'subst' ($(...) ou crase) | 'plain'
    """
    out = []
    i = 0
    n = len(command)
    start_plain = 0
    while i < n:
        ch = command[i]

        if ch == "\\" and i + 1 < n:
            i += 2
            continue

        if ch in ("'", '"'):
            if start_plain < i:
                out.append((start_plain, i, "plain", command[start_plain:i]))
            quote = ch
            j = i + 1
            while j < n:
                if command[j] == "\\" and quote == '"':
                    j += 2
                    continue
                if command[j] == quote:
                    break
                j += 1
            out.append((i, min(j + 1, n), "quoted", command[i + 1:j]))
            i = min(j + 1, n)
            start_plain = i
            continue

        if ch == "$" and i + 1 < n and command[i + 1] == "(":
            if start_plain < i:
                out.append((start_plain, i, "plain", command[start_plain:i]))
            depth = 1
            j = i + 2
            while j < n and depth:
                if command[j] == "(":
                    depth += 1
                elif command[j] == ")":
                    depth -= 1
                j += 1
            out.append((i, j, "subst", command[i + 2:j - 1]))
            i = j
            start_plain = i
            continue

        if ch == "`":
            if start_plain < i:
                out.append((start_plain, i, "plain", command[start_plain:i]))
            j = command.find("`", i + 1)
            if j == -1:
                j = n
            out.append((i, j + 1, "subst", command[i + 1:j]))
            i = j + 1
            start_plain = i
            continue

        i += 1

    if start_plain < n:
        out.append((start_plain, n, "plain", command[start_plain:n]))
    return out


def _preceding_token(command, pos):
    """Ultimo token nao-vazio antes de pos."""
    head = command[:pos].rstrip()
    if not head:
        return ""
    return head.split()[-1] if head.split() else ""


# `<<` e `<<-` com tag opcionalmente aspada. `<<<` (here-string) nao abre corpo.
_HEREDOC_OP = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
_SEGMENT_SPLIT = re.compile(r"&&|\|\||;|\||\(")
_PIPE_TO_SHELL = re.compile(r"\|\s*(?:sudo\s+)?(%s)\b" % "|".join(SHELLS))


def _feeds_shell(line, op):
    """O corpo deste operador vai ser executado por um interpretador?

    Olha o comando DONO do operador (o segmento entre o ultimo separador e o `<<`), e nao o
    primeiro comando da linha: em `cd x && python3 - <<EOF` o dono e' python3, nao cd. Tambem
    conta pipe para shell depois do operador (`cat <<EOF | bash`).
    """
    segment = _SEGMENT_SPLIT.split(line[:op.start()])[-1].split()
    words = [w for w in segment if "=" not in w or w.startswith("-")]
    owner = words[0].rsplit("/", 1)[-1] if words else ""
    return owner in SHELLS or bool(_PIPE_TO_SHELL.search(line[op.end():]))


def _heredoc_bodies(command, with_spans=False):
    """Devolve (corpos_executados, corpos_de_dado) dos heredocs do comando.

    `bash <<EOF` executa o corpo; `cat > f <<EOF` apenas o grava.

    Leitura sequencial, como o shell faz: cada operador consome o PROXIMO corpo, na ordem, e o
    corpo termina na linha igual a tag. A versao anterior procurava o corpo por regex a partir
    do texto do operador, e errava em dois casos reais, os dois bloqueando gravacao de texto:
    operador seguido de `&& ...` na mesma linha (o corpo nao era achado e virava comando) e dois
    heredocs com a mesma tag (so' o primeiro corpo era removido).
    """
    executed, data = [], []
    lines = command.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        for op in _HEREDOC_OP.finditer(line):
            strip_tabs, tag = op.group(1) == "-", op.group(3)
            start = i
            while i < len(lines):
                candidate = lines[i].lstrip("\t") if strip_tabs else lines[i]
                if candidate.rstrip() == tag:
                    break
                i += 1
            body = (start, i)
            i += 1
            (executed if _feeds_shell(line, op) else data).append(body)
    if with_spans:
        return executed, data
    text = lambda span: "\n".join(lines[span[0]:span[1]])
    return [text(b) for b in executed], [text(b) for b in data]


def strip_data_heredocs(command):
    """Remove do texto os corpos de heredoc que NAO sao executados.

    Necessario porque o corpo de um heredoc e' texto "plano" para o analisador de spans: sem
    esta remocao, um heredoc passado por stdin a um comando que nao e' shell teria o corpo
    inteiro tratado como comando. Foi exatamente assim que este modulo bloqueou o commit que
    o corrigia. Remove por linha, nao por busca de texto: um corpo repetido ou um trecho igual
    em outro lugar do comando nao pode ser removido no lugar errado.
    """
    _executed, data = _heredoc_bodies(command, with_spans=True)
    if not data:
        return command
    drop = set()
    for start, end in data:
        drop.update(range(start, end))
    return "\n".join(l for n, l in enumerate(command.split("\n")) if n not in drop)


def executable_text(command):
    """Concatena apenas o que o shell vai EXECUTAR.

    O que sobra de fora — argumento entre aspas de um echo, grep ou printf, corpo de heredoc
    gravado em arquivo — e' dado, e nao deve disparar guarda de comando.
    """
    if not command:
        return ""

    command = strip_data_heredocs(command)
    parts = []
    for start, _end, kind, content in _spans(command):
        if kind == "plain":
            parts.append(content)
        elif kind == "subst":
            # Substituicao de comando sempre executa.
            parts.append(content)
        else:  # quoted
            prev = _preceding_token(command, start)
            if prev in EXEC_AFTER or prev.endswith("/eval"):
                parts.append(content)
            else:
                # Dado. Preserva um espaco para nao colar tokens vizinhos.
                parts.append(" ")

    executed_bodies, _data_bodies = _heredoc_bodies(command)
    parts.extend(executed_bodies)

    return " ".join(p for p in parts if p is not None)


def data_text(command):
    """O complemento: o que e' apenas dado. Util para diagnostico e para os testes."""
    if not command:
        return ""
    parts = []
    for start, _end, kind, content in _spans(command):
        if kind == "quoted":
            prev = _preceding_token(command, start)
            if prev not in EXEC_AFTER and not prev.endswith("/eval"):
                parts.append(content)
    _executed, data_bodies = _heredoc_bodies(command)
    parts.extend(data_bodies)
    return " ".join(parts)
