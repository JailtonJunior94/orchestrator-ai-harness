Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
Não dá para corrigir nenhum bug a partir desse arquivo. Ele não descreve um bug real.

**Por que não dá para agir:**

- **O nome `bugs-invalido.json` sugere uma fixture feita para ser inválida.** Ela deve existir para testar se o validador ou a eval rejeita relatórios de bug malformados.
- **O relatório não tem nada que se possa usar:**
  - `"line": 0` não é uma linha válida, porque as linhas começam em 1.
  - `"reproduction": "x"`, `"expected": "y"` e `"actual": "z"` são textos de preenchimento. Não dizem qual é a entrada, o que se espera nem o que acontece.
- **Não recebi o `calc/media.go`**, então não tenho código para analisar nem corrigir.

Se eu "consertasse" a fixture, por exemplo trocando a linha para 1 e preenchendo textos plausíveis, ela provavelmente passaria a ser válida. Aí o teste que depende dela ser rejeitada pararia de fazer sentido.

**O que você quer fazer?**

1. **Corrigir um bug real em `calc/media.go`:** me mande o conteúdo do arquivo e diga o que está errado (a entrada, o resultado esperado e o resultado obtido).
2. **Ajustar a fixture:** diga o que ela deveria testar. Por exemplo, se ela deve falhar só por `line: 0`, os outros campos podem ficar realistas para isolar esse único erro.
3. **Criar uma fixture válida à parte** (algo como `bugs-valido.json`) para comparar com esta.
RESPOSTA>>>
