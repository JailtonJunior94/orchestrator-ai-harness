package com.example.orders;

public class Order {
    private String status = "DRAFT";

    public void pay() {
        if (status.equals("DRAFT")) {
            status = "PAID";
        } else if (status.equals("PAID") || status.equals("SHIPPED")) {
            throw new IllegalStateException("order already paid");
        } else if (status.equals("CANCELLED")) {
            throw new IllegalStateException("cancelled order cannot be paid");
        }
    }

    public void ship() {
        if (status.equals("PAID")) {
            status = "SHIPPED";
        } else if (status.equals("DRAFT")) {
            throw new IllegalStateException("order not paid");
        } else if (status.equals("SHIPPED")) {
            throw new IllegalStateException("order already shipped");
        } else if (status.equals("CANCELLED")) {
            throw new IllegalStateException("cancelled order cannot be shipped");
        }
    }

    public void cancel() {
        if (status.equals("DRAFT") || status.equals("PAID")) {
            status = "CANCELLED";
        } else if (status.equals("SHIPPED")) {
            throw new IllegalStateException("shipped order cannot be cancelled");
        }
    }

    public boolean canEditItems() {
        return status.equals("DRAFT");
    }

    public String getStatus() {
        return status;
    }
}
