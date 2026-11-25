CREATE TABLE IF NOT EXISTS service_availability (
    service TEXT PRIMARY KEY CHECK (service IN ('ai_router', 'telegram_bot')),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO service_availability (service)
VALUES ('ai_router'), ('telegram_bot')
ON CONFLICT (service) DO NOTHING;
