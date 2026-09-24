CREATE TABLE invoices (
    id serial PRIMARY KEY,
    customer_email varchar(255),
    amount float,
    currency varchar(255),
    issued_at timestamp,
    paid_at timestamp
);
