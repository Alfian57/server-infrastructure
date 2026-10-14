-- =============================================================================
-- Aldera AI API Relay Platform - Initial Model Pricing Seed Catalog
-- Target File: database/seeds/001_initial_pricing.sql
-- Currency: IDR per 1,000,000 (1M) tokens
-- Precision: NUMERIC(16, 4)
-- Idempotency: ON CONFLICT (model_name) DO UPDATE
-- =============================================================================

\set ON_ERROR_STOP on

INSERT INTO model_pricing (model_name, display_name, input_price_per_m, output_price_per_m, is_active)
VALUES
    ('gpt-4o', 'GPT-4o (Omni)', 45000.0000, 180000.0000, true),
    ('gpt-4o-mini', 'GPT-4o Mini', 2500.0000, 10000.0000, true),
    ('claude-3-5-sonnet-20241022', 'Claude 3.5 Sonnet v2', 48000.0000, 240000.0000, true),
    ('claude-3-5-haiku-20241022', 'Claude 3.5 Haiku', 15000.0000, 75000.0000, true),
    ('deepseek-chat', 'DeepSeek V3', 2000.0000, 4000.0000, true),
    ('deepseek-reasoner', 'DeepSeek R1', 8000.0000, 32000.0000, true)
ON CONFLICT (model_name) DO UPDATE
SET display_name = EXCLUDED.display_name,
    input_price_per_m = EXCLUDED.input_price_per_m,
    output_price_per_m = EXCLUDED.output_price_per_m,
    is_active = EXCLUDED.is_active,
    updated_at = clock_timestamp();
