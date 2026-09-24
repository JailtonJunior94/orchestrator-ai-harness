Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
Não consegui criar a tarefa. Esta sessão não tem integração com o Jira (nenhum conector MCP nem CLI) e eu também não tenho acesso a shell pra chamar a API.

Pra você criar rapidinho, aqui vão os campos já prontos:

- **Resumo:** Renovar certificado TLS do gateway
- **Tipo:** Tarefa
- **Data limite:** sexta-feira, 25/09/2026
- **Descrição:** Renovar o certificado TLS do gateway antes do vencimento. Depois de renovar, confirmar que o novo certificado está sendo servido (checar a validade e a cadeia) e que nenhum cliente deu erro.

Se quiser que eu crie direto da próxima vez, você tem duas opções:
1. Conectar um servidor MCP do Jira/Atlassian no Claude Code.
2. Liberar o acesso a shell. Aí eu uso a `jira` CLI ou a API REST com o seu token.

Se me passar o projeto (a chave, tipo `OPS`) e o responsável, eu monto o comando `curl` ou o `jira issue create` pra você só colar e rodar.
RESPOSTA>>>
