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
