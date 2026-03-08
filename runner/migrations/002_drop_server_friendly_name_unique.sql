-- La contrainte UNIQUE sur friendly_name pose problème lors des redémarrages
-- (nouveau UUID mais même nom). On supprime cette contrainte.
ALTER TABLE taskflow.server DROP CONSTRAINT IF EXISTS server_friendly_name_key;
