# Testes

<!-- TL;DR
Regras de testes (R-TEST-001): comportamento de domínio e use cases obrigatoriamente testados, testes determinísticos sem estado global e cobertura mínima enforced.
Keywords: teste, R-TEST-001, cobertura, determinístico, domínio, use-case, regressão
Load complete when: tarefa envolve garantir confiabilidade, cobertura de testes ou validação de adapters e integrações.
-->

- Rule ID: R-TEST-001
- Severidade: hard para correção e determinismo, guideline para estilo

## Objetivo
Garantir confiabilidade do código, dos adapters e das integrações.

## Requisitos

### Cobertura Prioritária
- Validadores de input devem ter testes unitários.
- Fluxos principais devem cobrir caminho feliz e cenários de falha.
- Integrações externas devem ter testes com doubles de subprocesso ou mock.
- Persistência e IO devem ter testes de integração com filesystem temporário.

### Estratégia
- Testes unitários devem usar doubles simples e determinísticos.
- Testes de integração devem validar filesystem e compatibilidade quando possível.
- Casos com matriz de entrada devem usar table-driven tests.

### Ferramentas
- Para diretrizes detalhadas de ferramentas de teste em Go (testify, mockery, fuzz): **Camada de linguagem é opcional** — a skill `lt:go-implementation` pode não estar instalada. Confirme antes de tentar carregá-la:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language`.
  Saída vazia significa que a camada não está instalada — siga com o que esta referência já diz.

### Determinismo
- Testes não devem depender de rede real nem de ferramentas externas instaladas.
- Tempo, IO e subprocesso devem ser abstraídos para teste.
- Estado compartilhado entre casos é proibido.

### Gates
- O comando de teste padrão do projeto deve ser o gate mínimo.
- Suites separadas devem ser claramente documentadas.

## Proibido
- Teste unitário chamando ferramentas externas reais.
- Testes frágeis baseados em `sleep`.
- Cobrir apenas o caminho feliz.
