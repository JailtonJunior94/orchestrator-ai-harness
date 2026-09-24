ALTER TABLE orders ADD COLUMN customer_id bigint;

ALTER TABLE orders
    ADD CONSTRAINT orders_customer_id_fkey
    FOREIGN KEY (customer_id) REFERENCES customers (id);

CREATE INDEX orders_customer_id_idx ON orders (customer_id);

ALTER TABLE orders ALTER COLUMN total TYPE numeric(14, 2);

ALTER TABLE orders ALTER COLUMN status SET NOT NULL;
