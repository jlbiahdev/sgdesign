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

-- =============================================================================
-- v2 — DB-driven dispatch
-- =============================================================================

-- Le settings.json est toujours à model_job.template_folder + "\settings.json".
-- Aucune colonne supplémentaire nécessaire.

-- Fonction déclenchée par le trigger ci-dessous.
-- Envoie une notification LISTEN/NOTIFY dès qu'un data_job passe à l'état 'Queued',
-- ce qui permet au Scheduler de réagir en quasi-temps réel sans polling agressif.
CREATE OR REPLACE FUNCTION public.hpclite_notify_job_ready()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state = 'Queued' AND (TG_OP = 'INSERT' OR OLD.state IS DISTINCT FROM 'Queued') THEN
        PERFORM pg_notify('hpclite_job_ready', NEW.parent_model_id::text);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hpclite_job_ready ON public.data_job;
CREATE TRIGGER trg_hpclite_job_ready
    AFTER INSERT OR UPDATE ON public.data_job
    FOR EACH ROW
    EXECUTE FUNCTION public.hpclite_notify_job_ready();
