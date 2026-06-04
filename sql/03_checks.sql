-- ============================================================
-- skiGIS | 03_checks.sql
-- ============================================================
-- Purpose : Quick verification queries to run after each
--           pipeline execution or when debugging.
--           Run individually — highlight and Ctrl+Enter.
-- ============================================================


-- ------------------------------------------------------------
-- CHECK 1 — Latest weather ingest
-- Did the most recent pipeline run land a row?
-- Look for: fresh timestamp, non-null snow_depth_in / swe_in
-- ------------------------------------------------------------

SELECT *
FROM "skiGIS".weather_logs
ORDER BY capture_time DESC
LIMIT 5;


-- ------------------------------------------------------------
-- CHECK 2 — Table row counts
-- Quick sanity check on all three core tables
-- ------------------------------------------------------------

SELECT 'weather_logs'           AS table_name, COUNT(*) AS row_count FROM "skiGIS".weather_logs
UNION ALL
SELECT 'ski_runs'               AS table_name, COUNT(*) AS row_count FROM "skiGIS".ski_runs
UNION ALL
SELECT 'potential_hazard_zones' AS table_name, COUNT(*) AS row_count FROM "skiGIS".potential_hazard_zones;


-- ------------------------------------------------------------
-- CHECK 3 — Geometry types and SRIDs
-- All analysis tables should be EPSG:4326
-- ------------------------------------------------------------

SELECT
    f_table_name        AS table_name,
    f_geometry_column   AS geom_column,
    type                AS geom_type,
    srid
FROM geometry_columns
WHERE f_table_schema = 'skiGIS'
ORDER BY f_table_name;


-- ------------------------------------------------------------
-- CHECK 4 — Geometry validity
-- Should return 0 rows if ST_MakeValid was run in setup
-- ------------------------------------------------------------

SELECT hazard_id, ST_IsValidReason(geom)
FROM "skiGIS".potential_hazard_zones
WHERE NOT ST_IsValid(geom);

SELECT id, ST_IsValidReason(geom)
FROM "skiGIS".ski_runs
WHERE NOT ST_IsValid(geom);


-- ------------------------------------------------------------
-- CHECK 5 — Unique constraint exists on weather_logs
-- contype = 'u' confirms the unique constraint is in place
-- Required for ON CONFLICT DO NOTHING to work in Python ingest
-- ------------------------------------------------------------

SELECT conname, contype
FROM pg_constraint
WHERE conrelid = '"skiGIS".weather_logs'::regclass;


-- ------------------------------------------------------------
-- CHECK 6 — Current risk assessment
-- The main output — run after every pipeline execution
-- ------------------------------------------------------------

SELECT * FROM "skiGIS".vw_run_risk_assessment;


-- ------------------------------------------------------------
-- CHECK 7 — Weather log column structure
-- Run if you suspect a schema mismatch with the Python insert
-- ------------------------------------------------------------

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'skiGIS'
  AND table_name   = 'weather_logs'
ORDER BY ordinal_position;


-- ------------------------------------------------------------
-- CHECK 8 — New snow delta (standalone)
-- Useful to run independently to verify depth delta logic
-- ------------------------------------------------------------

SELECT
    a.station_id,
    a.capture_time                                      AS current_time,
    b.capture_time                                      AS previous_time,
    a.snow_depth_in                                     AS depth_now,
    b.snow_depth_in                                     AS depth_prev,
    GREATEST(a.snow_depth_in - b.snow_depth_in, 0)     AS new_snow_approx_in
FROM "skiGIS".weather_logs a
JOIN "skiGIS".weather_logs b
    ON a.station_id = b.station_id
    AND b.capture_time = (
        SELECT MAX(capture_time)
        FROM "skiGIS".weather_logs
        WHERE station_id = a.station_id
          AND capture_time < a.capture_time
    )
WHERE a.capture_time = (
    SELECT MAX(capture_time)
    FROM "skiGIS".weather_logs
    WHERE station_id = '846'
)
ORDER BY a.capture_time DESC;

