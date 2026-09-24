Toda transportadora nova obriga a mexer nos dois switch de evals/fixtures/shipping/shipping-cost.ts. Qual design pattern resolve isso?

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/shipping/shipping-cost.ts`:

```
export type Carrier = "correios" | "jadlog" | "loggi" | "azul-cargo";

export interface Parcel {
  weightKg: number;
  distanceKm: number;
  express: boolean;
}

export function shippingCost(carrier: Carrier, parcel: Parcel): number {
  switch (carrier) {
    case "correios":
      return 12 + parcel.weightKg * 1.8 + (parcel.express ? 15 : 0);
    case "jadlog":
      return 9 + parcel.weightKg * 2.1 + parcel.distanceKm * 0.02;
    case "loggi":
      return parcel.distanceKm > 50 ? 30 : 18 + parcel.weightKg * 1.2;
    case "azul-cargo":
      return 25 + parcel.weightKg * 3 + (parcel.express ? 20 : 0);
  }
}

export function estimatedDays(carrier: Carrier, parcel: Parcel): number {
  switch (carrier) {
    case "correios":
      return parcel.express ? 2 : 7;
    case "jadlog":
      return Math.ceil(parcel.distanceKm / 400) + 1;
    case "loggi":
      return parcel.distanceKm > 50 ? 3 : 1;
    case "azul-cargo":
      return 1;
  }
}
```
