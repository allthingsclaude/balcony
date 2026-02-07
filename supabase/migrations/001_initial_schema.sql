-- Balcony Cloud Relay Schema (Phase 2)
-- This migration creates the initial tables for device pairing and message relay.

-- Devices table
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('macOS', 'iOS')),
    public_key TEXT NOT NULL,
    fcm_token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pairings table
CREATE TABLE pairings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mac_device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    ios_device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    shared_secret_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(mac_device_id, ios_device_id)
);

-- Relay messages table (ephemeral, for store-and-forward)
CREATE TABLE relay_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pairing_id UUID REFERENCES pairings(id) ON DELETE CASCADE,
    direction TEXT NOT NULL CHECK (direction IN ('mac_to_ios', 'ios_to_mac')),
    encrypted_payload BYTEA NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '1 hour'),
    delivered BOOLEAN DEFAULT FALSE
);

-- Row-Level Security
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE pairings ENABLE ROW LEVEL SECURITY;
ALTER TABLE relay_messages ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can manage their own devices"
    ON devices FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users can see their pairings"
    ON pairings FOR ALL
    USING (
        mac_device_id IN (SELECT id FROM devices WHERE user_id = auth.uid())
        OR ios_device_id IN (SELECT id FROM devices WHERE user_id = auth.uid())
    );

-- Indexes
CREATE INDEX idx_relay_messages_pairing ON relay_messages(pairing_id, delivered);
CREATE INDEX idx_relay_messages_expires ON relay_messages(expires_at) WHERE NOT delivered;
