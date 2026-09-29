# Principios de Teste (Cross-Linguagem)

<!-- TL;DR
Princípios de teste cross-linguagem: testes determinísticos e eficazes, mocks apenas em fronteiras externas, nomenclatura por cenário, e2e só para jornadas críticas e cobertura dentro da faixa de R-TEST-002.
Keywords: teste, unit, integração, e2e, mock, determinístico, cobertura, eficácia, cross-linguagem
Load complete when: tarefa envolve estratégia de testes, cobertura ou uso de mocks em qualquer linguagem.
-->

- Rule ID: R-XTEST-001
- Severidade: guideline
- Escopo: estratégia de testes cross-linguagem.
- Regra-mãe: `R-TEST-002` em `config/constitution.md` (piso de cobertura, eficácia, zero lacuna).

## Unit Tests (obrigatorio)
- Todo comportamento de dominio, use case e logica pura deve ter unit test.
- Nomear pelo cenario, nao pelo metodo.
- Testes deterministicos: sem sleep, sem dependencia de ordem, sem estado global.
- Mocks apenas para fronteiras externas (IO, rede, filesystem, banco).
- Nao testar glue code sem logica (construtores triviais, DTOs, wiring).

## Integration Tests (quando adotados)
- Separar de unit tests via tag, marcador ou script dedicado.
- Usar testcontainers para provisionar dependencias reais em containers efemeros.
- Cada suite provisiona e destroi seu container — nao depender de infra pre-existente.
- Nao depender de servicos externos reais (banco de dev, API de staging).

## E2E Tests (jornadas criticas)
- Um fluxo por jornada critica de negocio, nao um por requisito.
- Dados proprios criados e removidos pelo teste; sem dependencia de ordem entre cenarios.
- Esperar por condicao observavel (resposta, elemento, evento), nunca por tempo fixo.
- Nao repetir em e2e o que unit e integracao ja provam.

## Proibido
- Sleep para sincronizacao em teste.
- Teste que passa sozinho mas falha em suite completa.
- Mock que nao reflete o contrato real da dependencia.
- Integration test sem separacao rodando junto com unit tests.
- Teste sem assercao, ou cuja unica assercao e "o mock foi chamado".
- Teste escrito so para subir o numero de cobertura.
