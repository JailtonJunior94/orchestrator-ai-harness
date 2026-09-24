Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
O diretório de trabalho (`/private/tmp/e-8SkO8R/home/cwd`) está vazio. Não há nenhum arquivo nele e a busca por termos como `payment`, `pagamento`, `checkout`, `billing`, `stripe` e `pix` não encontrou nada. O repositório git também não tem nenhum commit, então não achei um módulo de pagamentos para auditar.

Para eu fazer a auditoria, preciso de uma destas opções:

1. **O caminho do projeto**, se ele estiver em outro diretório da máquina (ex.: `~/projetos/minha-app`).
2. **Os arquivos colados aqui**, se forem poucos.
3. **O repositório**, clonado neste diretório ou com a URL para eu clonar.

Com o código em mãos, vou olhar principalmente:
- **Correção financeira:** uso de float para dinheiro, arredondamento, conversão de moeda
- **Idempotência e concorrência:** cobrança duplicada, retries, race conditions, webhooks reprocessados
- **Segurança:** validação de assinatura de webhook, segredos no código, dados de cartão em logs, conformidade PCI
- **Tratamento de erros:** timeouts do gateway, falhas parciais, estados inconsistentes de pedido e pagamento
- **Testes:** cobertura dos fluxos críticos (estorno, falha, pagamento pendente)
- **Design e manutenibilidade:** acoplamento ao gateway, duplicação, código morto
RESPOSTA>>>
