Revisa evals/fixtures/checkout/CheckoutService.java com Object Calisthenics. É código de produção.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/checkout/CheckoutService.java`:

```
package shop.checkout;

public class CheckoutService {
    private final Mailer mailer;
    private final ShippingRates rates;

    public CheckoutService(Mailer mailer, ShippingRates rates) {
        this.mailer = mailer;
        this.rates = rates;
    }

    public double shippingCost(Order order) {
        String city = order.getCustomer().getAddress().getCity();
        if (order.getItems().size() > 0) {
            if (order.getCustomer().isPremium()) {
                return 0;
            } else {
                return rates.forCity(city);
            }
        } else {
            return 0;
        }
    }

    public void confirm(Order order) {
        String email = order.getCustomer().getEmail();
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException("invalid email");
        }
        mailer.send(email.trim().toLowerCase(), "Order confirmed");
    }

    public void sendInvoice(Order order, String invoiceUrl) {
        String email = order.getCustomer().getEmail();
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException("invalid email");
        }
        mailer.send(email.trim().toLowerCase(), "Invoice: " + invoiceUrl);
    }
}
```
