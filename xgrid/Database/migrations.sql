-- Styx migrations

-- Table schedulers (à créer)
CREATE TABLE IF NOT EXISTS public.schedulers (
    id           BIGSERIAL PRIMARY KEY,
    pid          INTEGER NOT NULL,
    host         TEXT NOT NULL,
    model_job_id BIGINT REFERENCES model_job(id),
    job_path     TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'active',  -- active | dead
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    heartbeat    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Colonnes à ajouter sur model_job
ALTER TABLE public.model_job
    ADD COLUMN IF NOT EXISTS scheduler_id BIGINT REFERENCES schedulers(id);

ALTER TABLE public.model_job
    ADD COLUMN IF NOT EXISTS job_path TEXT;

-- Index pour les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_schedulers_status_heartbeat ON public.schedulers (status, heartbeat);
CREATE INDEX IF NOT EXISTS idx_data_job_parent_model_id    ON public.data_job (parent_model_id);
