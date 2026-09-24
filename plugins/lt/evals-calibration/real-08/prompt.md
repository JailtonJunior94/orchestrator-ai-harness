Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
Não consegui corrigir porque não encontrei o código. O diretório de trabalho (`/private/tmp/e-iv2uOX/home/cwd`) está vazio. Também procurei "csv" em `/private/tmp/e-iv2uOX/home`, que é a raiz do repositório git, e não achei nada. O repositório não tem nenhum commit, e os únicos arquivos fora do controle de versão são `.aws/` e `.gitconfig`.

Para seguir, preciso de uma destas coisas:

1. **O caminho do projeto** onde está o export de CSV, se ele estiver em outro diretório.
2. **O código do export**, colado aqui: a função que gera o CSV e a que busca os dados.

Se tiver, mande também:
- A stack (Node, Python, etc.) e se o export roda no backend ou no navegador.
- Quando ele vem vazio: sem nem o cabeçalho, ou só com o cabeçalho?
- Algum padrão: acontece mais com arquivos grandes, com o servidor sob carga ou logo após salvar dados?

Quando um CSV vem vazio só às vezes, a causa costuma ser uma destas:
- Um `await` faltando antes de buscar os dados, e o arquivo é gerado antes da consulta terminar.
- Um stream que não recebe `flush` ou `end` antes da resposta ser enviada ou do arquivo ser lido.
- Uma escrita em arquivo temporário que é lida antes de terminar.
- Uma consulta que não vê dados salvos há pouco, por cache ou por ler de uma réplica atrasada.

Com o código em mãos, eu verifico essas hipóteses.
RESPOSTA>>>
