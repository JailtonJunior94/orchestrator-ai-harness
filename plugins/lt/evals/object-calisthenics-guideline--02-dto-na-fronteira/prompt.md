O OrderResponse em evals/fixtures/api/order-response.ts viola Object Calisthenics? Tem seis campos e nenhum comportamento.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/api/order-response.ts`:

```
import type { Order } from "../domain/order";

export interface OrderResponse {
  id: string;
  status: string;
  customerName: string;
  totalCents: number;
  currency: string;
  createdAt: string;
}

export function toOrderResponse(order: Order): OrderResponse {
  return {
    id: order.id,
    status: order.status,
    customerName: order.customerName(),
    totalCents: order.total().cents,
    currency: order.total().currency,
    createdAt: order.createdAt.toISOString(),
  };
}
```
