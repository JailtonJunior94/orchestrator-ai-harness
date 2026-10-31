# Relatório de Review (modo --auto-review)

- Veredito: APPROVED | APPROVED_WITH_REMARKS | REJECTED | BLOCKED
- Contexto: fresh | same-thread
<!-- `fresh` só quando a revisão rodou em subagente sem o histórico de quem escreveu o diff
     (I-3 da constitution). Na dúvida, `same-thread`. O validador exige a linha, não o valor:
     o que é proibido é esconder em qual contexto a revisão foi feita. -->
- Alvo revisado: [diff | branch | commit | lista de arquivos]
- Task file: [caminho da task revisada — obrigatório: o mapa 1:1 é confrontado contra os critérios dela (RF-51)]
- Refs carregadas: [referências disparadas, ou — se nenhuma]

## Mapa de Critérios de Aceite
<!-- OBRIGATÓRIO para TODA tarefa ativa (RF-47, RF-51). O confronto é incondicional:
     uma linha por critério de `## Critérios de Sucesso`/`## Critérios de Aceite` da task file.
     Formato literal de cada linha:
       - [atendido|não atendido|não verificável] <critério> -> <linha de evidência>
     A <linha de evidência> só é válida em uma das três formas (RF-48):
       (a) comando executado com saída registrada  — ex: go test ./... -> PASS
       (b) referência arquivo:linha presente no diff revisado — ex: internal/foo.go:42
       (c) nome de teste com resultado registrado — ex: TestFoo -> pass
     Critério "não verificável" PROÍBE o veredito APPROVED (RF-49) e vira achado de severidade alta.
     Seção ausente, critério sem evidência, marcador inválido ou mapa incompleto FALHAM o validador. -->
- [atendido|não atendido|não verificável] <critério> -> <linha de evidência>

## Achados
<!-- Para cada achado, repetir o bloco. Se não houver achados, escrever exatamente "Sem achados". -->
- Severidade: critical | high | medium | low
- Arquivo:
- Linha:
- Impacto:
- Dica de correção:

## Contestações
<!-- Opcional; só em rodada pós-bugfix (AI_REVIEW_PRIOR_SHA definido). Uma linha por achado que o
     executor contestou com evidência no relatório de execução:
       - BUG-NNN: retirado | sustentado -> <evidência avaliada> -->
- [BUG-NNN: retirado | sustentado -> evidência avaliada]

## Arquivos Revisados
- [caminho efetivamente lido]

## Riscos Residuais
- [risco]

## Validações Executadas
- [comando de validação executado ou consultado] -> [resultado]
