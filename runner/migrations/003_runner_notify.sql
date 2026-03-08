-- =============================================================
-- TaskFlow - Migration 003
-- Notification temps réel quand un runner s'enregistre / heartbeat
-- =============================================================

CREATE OR REPLACE FUNCTION taskflow.notify_runner_change()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify(
        'taskflow_runner_events',
        json_build_object(
            'id',              NEW.id,
            'friendlyName',    NEW.friendly_name,
            'lastHeartbeatAt', NEW.last_heartbeat_at
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_runner ON taskflow.server;
CREATE TRIGGER trg_notify_runner
    AFTER INSERT OR UPDATE ON taskflow.server
    FOR EACH ROW EXECUTE FUNCTION taskflow.notify_runner_change();
