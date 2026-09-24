Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
Adicionei a tarefa 3.0 para o RF-03 e a linha correspondente na tabela de cobertura. Não mexi em mais nada no bundle.

`evals/fixtures/bundle-extrato/tasks.md`:

```markdown
<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
<!-- spec-hash-techspec: 0000000000000000000000000000000000000000000000000000000000000000 -->
# Tasks — Extrato em CSV

| # | Tarefa | Status | Dependências | Paralelizável | Skills |
|---|---|---|---|---|---|
| 1.0 | Endpoint de exportação CSV | pending | — | — | — |
| 2.0 | Colunas data, descrição, valor e saldo | pending | 1.0 | — | — |
| 3.0 | Gravar evento `extrato.exportado` na trilha de auditoria a cada exportação | pending | 1.0 | com 2.0 | — |

## Cobertura de Requisitos

| Tarefa | Requisitos cobertos |
|---|---|
| 1.0 | RF-01 |
| 2.0 | RF-02 |
| 3.0 | RF-03 |
```

- **Dependência:** a 3.0 depende da 1.0 porque o evento é disparado quando o endpoint exporta o extrato. Ela não depende do formato das colunas, então pode rodar junto com a 2.0.
- **Hashes:** deixei como estavam. O PRD e a TechSpec não mudaram, e esses valores zerados parecem ser placeholders da fixture. Se o validate-sdd também confere os hashes, eles precisam ser atualizados à parte.

Não rodei o validate-sdd de novo porque o repositório não está disponível nesta sessão. Vale rodar para confirmar que o aviso sobre o RF-03 sumiu.
RESPOSTA>>>
