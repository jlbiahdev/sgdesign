-- HpcLite migrations
-- Run once against the PostgreSQL database

-- Nœuds Scheduler (pré-insérés par un admin)
CREATE TABLE IF NOT EXISTS public.schedulers (
    id         BIGSERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    host       TEXT NOT NULL UNIQUE,
    status     TEXT NOT NULL DEFAULT 'inactive', -- inactive | active | dead
    started_at TIMESTAMPTZ,
    heartbeat  TIMESTAMPTZ
);

-- Nœuds Runner (pré-insérés par un admin)
CREATE TABLE IF NOT EXISTS public.runners (
    id           BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    host         TEXT NOT NULL,
    exe_path     TEXT NOT NULL,           -- chemin vers HpcLite.Runner.exe sur la machine Runner
    status       TEXT NOT NULL DEFAULT 'idle', -- idle | active | dead
    pid          INTEGER,
    model_job_id BIGINT REFERENCES model_job(id),
    started_at   TIMESTAMPTZ,
    heartbeat    TIMESTAMPTZ
);

-- Ajout de la FK runner sur model_job
ALTER TABLE public.model_job
    ADD COLUMN IF NOT EXISTS runner_id BIGINT REFERENCES runners(id);

-- Exemples d'insertions admin
-- INSERT INTO schedulers (name, host) VALUES ('Scheduler-01', 'HEADNODE-01');
-- INSERT INTO runners (name, host, exe_path)
--   VALUES ('Runner-01', 'COMPUTE-01', 'C:\apps\HpcLite.Runner\HpcLite.Runner.exe'),
--          ('Runner-02', 'COMPUTE-02', 'C:\apps\HpcLite.Runner\HpcLite.Runner.exe');
