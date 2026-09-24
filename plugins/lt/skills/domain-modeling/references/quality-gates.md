# Gates de Prontidão

<!-- TL;DR
Oito gates que o modelo cumpre antes do handoff para a techspec ou para a implementação; gate não cumprido é declarado, nunca omitido.
Keywords: gate, prontidão, handoff, checklist, qualidade
Load complete when: a etapa é relatar o modelo ou decidir se ele segue para a techspec.
-->

O modelo segue para handoff quando todos os gates passam ou quando a pessoa aceita
explicitamente o gate pendente como risco, registrado em `Itens em Aberto`.

| Gate | Passa quando |
|---|---|
| 1. Linguagem | Termo canônico para o fluxo principal; sinônimos ambíguos proibidos; nenhum termo técnico no lugar de termo de negócio |
| 2. Tipos | Todo conceito com regra é tipo restrito com construtor; cada estado do ciclo de vida é um tipo; nenhuma escolha codificada como opcionais combinados |
| 3. Workflows | Cada workflow tem comando, eventos, erro e dependências na assinatura; cita os `RF-NN` quando há PRD |
| 4. Invariantes | Invariante central explícita, com o mecanismo que a garante: tipo, etapa do workflow ou restrição de persistência |
| 5. Erros | Erros de domínio nomeados por reação distinta; erro de infraestrutura fora do tipo de erro do domínio |
| 6. Fronteiras | Bounded contexts e relações registrados; DTO e tradução separados do tipo de domínio |
| 7. Evidência | Comportamento existente com `path:linha` ou `greenfield` declarado; nenhuma suposição apresentada como fato |
| 8. Economia | Cada contexto, agregado, evento e estado novo tem justificativa; o desenho é o menor que preserva as invariantes |
