-- Records what kind of machine a sync device is (android / windows / linux /
-- macos), so the Sync Center can show a meaningful device list instead of a
-- wall of identical "Device" rows. NULL for devices that registered before
-- this column existed; clients send it on every manifest call.
ALTER TABLE sync_devices ADD COLUMN platform TEXT;

-- Distinguishes the machine the user is looking at from the others in the
-- list. Clients send their own device id, so the server can mark it.
CREATE INDEX IF NOT EXISTS sync_devices_user_seen_idx
    ON sync_devices(user_id, last_seen_at DESC);
