Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
Não consegui fazer a auditoria porque não encontrei nenhum módulo de pagamentos.

- **Diretório de trabalho vazio:** `/private/tmp/e-MSpPO7/home/cwd` não tem nenhum arquivo.
- **Nenhuma referência no diretório acima:** procurei por "payment" e "pagamento" em `/private/tmp/e-MSpPO7/home` e não achei nada. O repositório git também não tem nenhum commit, só `.aws/` e `.gitconfig` não rastreados, que não são código.

Para continuar, preciso de uma destas opções:

1. **O caminho do módulo**, se ele estiver em outro diretório ou repositório.
2. **Que você clone ou copie o código** para cá.
3. **Um diff, branch ou PR específico.** Nesse caso posso usar a revisão do harness LT (`lt:review`), que cobre correção, segurança, regressões e testes faltantes.

Quando o código estiver acessível, a auditoria vai cobrir:
- como os valores monetários são representados (float ou decimal/centavos)
- idempotência das cobranças e dos webhooks
- tratamento de erros e retentativas com o gateway
- validação da assinatura dos webhooks
- dados sensíveis (PAN/CVV) em logs
- transações e concorrência
- cobertura de testes
RESPOSTA>>>
