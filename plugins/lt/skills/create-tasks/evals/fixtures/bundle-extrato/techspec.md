<!-- spec-hash-prd: 0000000000000000000000000000000000000000000000000000000000000000 -->
# TechSpec — Extrato em CSV

## Arquitetura
- Endpoint GET /extratos/{mes}.csv no serviço de extrato (RF-01, RF-02).
- Evento `extrato.exportado` gravado na trilha de auditoria (RF-03).
