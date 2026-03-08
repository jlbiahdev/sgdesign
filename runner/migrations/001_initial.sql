-- =============================================================
-- TaskFlow - Migration initiale
-- Schéma : taskflow
-- =============================================================

CREATE SCHEMA IF NOT EXISTS taskflow;

-- -------------------------------------------------------------
-- Suivi des runners actifs
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS taskflow.server (
    id               VARCHAR(255) PRIMARY KEY,
    friendly_name    VARCHAR(255) UNIQUE,
    last_heartbeat_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------
-- Table principale des tâches
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS taskflow.task (
    id           BIGSERIAL PRIMARY KEY,
    external_id  BIGINT NOT NULL,
    state        VARCHAR(20) NOT NULL DEFAULT 'Submitted',
    command_type VARCHAR(10) NOT NULL DEFAULT 'Shell',   -- 'Shell' | 'DotNet'
    exe_name     VARCHAR(255) NOT NULL,
    args         TEXT,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_task_state ON taskflow.task (state, created_at);

-- -------------------------------------------------------------
-- Historique des transitions d'état
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS taskflow.task_state (
    id         BIGSERIAL PRIMARY KEY,
    task_id    BIGINT NOT NULL REFERENCES taskflow.task(id) ON DELETE CASCADE,
    name       VARCHAR(20) NOT NULL,
    reason     TEXT,
    server_id  VARCHAR(255) REFERENCES taskflow.server(id),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_task_state_task_id ON taskflow.task_state (task_id, created_at);

-- -------------------------------------------------------------
-- Compteur de tentatives par tâche (pour retry future)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS taskflow.attempt_counter (
    id      BIGSERIAL PRIMARY KEY,
    task_id BIGINT NOT NULL UNIQUE REFERENCES taskflow.task(id) ON DELETE CASCADE,
    count   INT NOT NULL DEFAULT 0
);

-- -------------------------------------------------------------
-- Fonction de notification automatique sur changement d'état
-- Déclenche un NOTIFY 'taskflow_events' à chaque INSERT dans task_state
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION taskflow.notify_task_state_change()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify(
        'taskflow_events',
        json_build_object(
            'taskId',   NEW.task_id,
            'state',    NEW.name,
            'serverId', NEW.server_id,
            'reason',   NEW.reason,
            'at',       NEW.created_at
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_task_state ON taskflow.task_state;
CREATE TRIGGER trg_notify_task_state
    AFTER INSERT ON taskflow.task_state
    FOR EACH ROW EXECUTE FUNCTION taskflow.notify_task_state_change();
