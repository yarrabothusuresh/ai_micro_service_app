create table postings (
    id uuid primary key,
    idempotency_key uuid not null unique,
    request_hash char(64) not null,
    reference varchar(80) not null check (length(trim(reference)) > 0),
    amount numeric(14,2) not null check (amount > 0),
    currency varchar(3) not null check (currency in ('INR','USD','EUR')),
    transaction_type varchar(16) not null check (transaction_type in ('SALE','PURCHASE','REFUND')),
    narration varchar(500) not null,
    account_code varchar(80) not null,
    account_name varchar(120) not null,
    rule_id varchar(120) not null,
    rule_version varchar(80) not null,
    created_at timestamptz not null default current_timestamp
);
create index postings_created_at_idx on postings (created_at desc, id desc);
