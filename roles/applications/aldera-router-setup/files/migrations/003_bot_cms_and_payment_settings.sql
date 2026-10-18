-- =============================================================================
-- Migration: 003_bot_cms_and_payment_settings.sql
-- Description: Telegram Bot Configs & Payment Method Settings tables
-- Database: aldera_router
-- =============================================================================

CREATE TABLE IF NOT EXISTS telegram_bot_configs (
    id VARCHAR(64) PRIMARY KEY DEFAULT 'default',
    ticket_template TEXT NOT NULL,
    important_notes TEXT NOT NULL,
    next_steps_notes TEXT NOT NULL,
    topup_amounts JSONB NOT NULL DEFAULT '[25000, 50000, 100000, 250000, 500000]'::jsonb,
    admin_telegram_username VARCHAR(128) NOT NULL DEFAULT 'aldera_admin',
    welcome_text TEXT,
    help_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_telegram_bot_configs_updated_at ON telegram_bot_configs;
CREATE TRIGGER trg_telegram_bot_configs_updated_at
    BEFORE UPDATE ON telegram_bot_configs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE IF NOT EXISTS payment_method_settings (
    id VARCHAR(64) PRIMARY KEY,
    type VARCHAR(32) NOT NULL DEFAULT 'BANK',
    name VARCHAR(128) NOT NULL,
    account_number VARCHAR(128) NOT NULL,
    account_name VARCHAR(128) NOT NULL,
    qris_image_url TEXT,
    instructions TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_method_settings_active ON payment_method_settings(is_active);
CREATE INDEX IF NOT EXISTS idx_payment_method_settings_display_order ON payment_method_settings(display_order);

DROP TRIGGER IF EXISTS trg_payment_method_settings_updated_at ON payment_method_settings;
CREATE TRIGGER trg_payment_method_settings_updated_at
    BEFORE UPDATE ON payment_method_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
