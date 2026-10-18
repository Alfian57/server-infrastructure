-- =============================================================================
-- Migration: 002_account_binding.sql
-- Description: Account binding tokens & Web user ID association
-- Database: aldera_router
-- =============================================================================

-- 1. Extend users table for Web Platform identity linking
ALTER TABLE users ADD COLUMN IF NOT EXISTS web_user_id VARCHAR(64) UNIQUE;
CREATE INDEX IF NOT EXISTS idx_users_web_user_id ON users(web_user_id);

-- Make telegram_id nullable to permit web-first client registrations prior to Telegram binding
ALTER TABLE users ALTER COLUMN telegram_id DROP NOT NULL;

-- 2. Create account_binding_tokens table
-- Stores time-bounded verification tokens for Web <-> Telegram Bot binding
CREATE TABLE IF NOT EXISTS account_binding_tokens (
    id BIGSERIAL PRIMARY KEY,
    token VARCHAR(64) NOT NULL UNIQUE,
    code VARCHAR(10) NOT NULL UNIQUE,
    aldera_user_id VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_binding_token_non_empty CHECK (length(trim(token)) >= 16),
    CONSTRAINT chk_binding_code_format CHECK (code ~ '^[0-9]{6}$'),
    CONSTRAINT chk_binding_user_id_non_empty CHECK (length(trim(aldera_user_id)) > 0)
);

-- Indexes for fast token verification and lifecycle queries
CREATE INDEX IF NOT EXISTS idx_binding_tokens_token ON account_binding_tokens(token);
CREATE INDEX IF NOT EXISTS idx_binding_tokens_code ON account_binding_tokens(code);
CREATE INDEX IF NOT EXISTS idx_binding_tokens_aldera_user_id ON account_binding_tokens(aldera_user_id);
CREATE INDEX IF NOT EXISTS idx_binding_tokens_expires_at ON account_binding_tokens(expires_at);
