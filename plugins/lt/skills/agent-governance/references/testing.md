# Testes

<!-- TL;DR
Regras de testes (R-TEST-001, operacionaliza R-TEST-002 da constitution): testar o que importa, cobertura por pacote tocado dentro da faixa da constitution, todo teste precisa derrubar o comportamento que protege, nível certo (unit, integração, e2e) para cada risco, zero regressão e todo RF com teste mapeado.
Keywords: teste, R-TEST-001, R-TEST-002, cobertura, eficácia, mutante, determinístico, domínio, use-case, integração, e2e, regressão
Load complete when: tarefa envolve escrever ou revisar testes, medir cobertura, definir estratégia de testes ou validar adapters e integrações.
-->

- Rule ID: R-TEST-001
- Severidade: hard para correção, eficácia e determinismo, guideline para estilo
- Regra-mãe: `R-TEST-002` em `config/constitution.md`. Números de cobertura e proibições absolutas
  vivem só lá; esta referência diz como cumprir.

## Objetivo
Garantir que a suíte pegue regressão real no código, nos adapters e nas integrações, com o menor
número de testes que dá essa garantia.

## Requisitos

### O que testar primeiro
- Regra de negócio, invariantes e transições de estado do domínio.
- Use cases: caminho feliz, cada falha de negócio e cada falha de dependência.
- Validadores de input, com as bordas (vazio, limite, formato inválido, overflow).
- Cada adapter de fronteira (banco, fila, cliente HTTP, filesystem) em teste de integração.
- Jornadas críticas de negócio em e2e.

### O que não testar
- Getter, setter, DTO, construtor trivial, wiring de injeção de dependência.
- Código de terceiro (framework, driver, SDK); teste o seu uso dele, no nível de integração.
- O mesmo ramo por dois caminhos diferentes.

### Eficácia
- Antes de escrever o teste, nomeie o comportamento que ele protege. Depois, pergunte: "se eu
  inverter esta condição, apagar esta linha ou trocar este valor, algum teste quebra?". Se não
  quebrar, o teste não protege nada.
- Asserção sobre o resultado observável (retorno, estado persistido, evento emitido, erro), não
  sobre detalhe interno nem só sobre a chamada do mock.
- Asserção exata: valor esperado, tipo de erro, campos relevantes. `not nil` e `len > 0` sozinhos
  não bastam.
- Mutation testing (go-mutesting, Stryker, mutmut, PIT) é ferramenta opcional para domínio crítico,
  não gate: custa caro por execução.

### Estratégia por nível
- Unit: doubles simples e determinísticos, só nas fronteiras externas. Matriz de entrada vira
  table-driven test.
- Integração: dependência real efêmera (testcontainers ou equivalente), provisionada e destruída
  pela própria suíte, separada dos unit tests por tag, marcador ou script.
- E2E: um fluxo por jornada crítica, com dados próprios e sem depender de ordem. Não replicar em e2e
  o que unit e integração já provam.

### Ferramentas
- Para diretrizes detalhadas de teste em Go (table tests, paralelismo, goleak, fuzz, benchmark): **Camada de linguagem é opcional**, e a skill `lt:go-guideline` pode não estar instalada. Confirme antes de tentar carregá-la:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language`.
  Se `go-guideline` não aparecer na saída, siga com o que esta referência já diz.

### Determinismo
- Testes não devem depender de rede real nem de ferramentas externas instaladas.
- Tempo, IO e subprocesso devem ser abstraídos para teste.
- Estado compartilhado entre casos é proibido.

### Gates
- O comando de teste padrão do projeto é o gate mínimo; suítes separadas (integração, e2e) ficam
  documentadas com o próprio comando.
- Medir a cobertura de cada pacote tocado antes e depois da tarefa, com a ferramenta nativa
  (`go test -coverprofile`, `pytest --cov`, `vitest --coverage`, `jest --coverage`), e registrar no
  bloco `## Coverage` do relatório. Pacote abaixo do piso de `R-TEST-002.1` reprova o `done`.
- Pacote abaixo do piso ganha testes pelos ramos de maior risco primeiro, não pelos mais fáceis.

## Proibido
- Teste unitário chamando ferramentas externas reais.
- Testes frágeis baseados em `sleep`.
- Cobrir apenas o caminho feliz.
- Teste escrito só para subir o número de cobertura.
- Apagar ou marcar como `skip` um teste que falha para destravar a tarefa.
