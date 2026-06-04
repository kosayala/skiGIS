-- ============================================================
-- skiGIS | 02_spatial_analysis.sql
-- ============================================================
-- Purpose : Core spatial analysis queries and the main risk
--           assessment view. Re-run the view block any time
--           the risk scoring logic needs to be updated.
-- Dependencies : 01_schema_setup.sql must be run first.
-- ============================================================


-- ------------------------------------------------------------
-- SECTION 1 — Ski Run / Hazard Zone Intersection
-- ------------------------------------------------------------
-- Shows which runs cross hazard terrain and what percentage
-- of each run's length falls inside a hazard polygon.
-- Ordered by exposure (highest first).
-- ------------------------------------------------------------

SELECT
    r.id                                                AS run_id,
    r.name                                              AS run_name,
    r."piste:difficulty"                                AS difficulty,
    r."piste:grooming"                                  AS grooming,
    COUNT(h.hazard_id)                                  AS hazard_zone_count,
    ROUND(
        (ST_Length(ST_Intersection(r.geom, ST_Union(h.geom))::geography)
        / ST_Length(r.geom::geography) * 100)::numeric
    , 1)                                                AS pct_run_in_hazard,
    ROUND(ST_Length(r.geom::geography)::numeric, 0)     AS run_length_m
FROM "skiGIS".ski_runs r
JOIN "skiGIS".potential_hazard_zones h
    ON ST_Intersects(r.geom, h.geom)
GROUP BY r.id, r.name, r."piste:difficulty", r."piste:grooming", r.geom
ORDER BY pct_run_in_hazard DESC;


-- ------------------------------------------------------------
-- SECTION 2 — New Snow Approximation (Depth Delta)
-- ------------------------------------------------------------
-- Station 846 (Virginia Lakes Ridge) does not have a dedicated
-- new snow sensor. We approximate 24hr new snow by calculating
-- the difference between the two most recent depth readings.
-- GREATEST(..., 0) prevents negative values from snow settling.
-- ------------------------------------------------------------

SELECT
    a.station_id,
    a.capture_time                                          AS current_time,
    b.capture_time                                          AS previous_time,
    a.snow_depth_in                                         AS depth_now,
    b.snow_depth_in                                         AS depth_prev,
    GREATEST(a.snow_depth_in - b.snow_depth_in, 0)         AS new_snow_approx_in
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


-- ------------------------------------------------------------
-- SECTION 3 — Risk Assessment View
-- ------------------------------------------------------------
-- Combines terrain exposure, new snow loading, and snowpack
-- weight (SWE) into a composite 0-100 risk score per ski run.
--
-- Risk Score Components:
--   Terrain exposure (0-50 pts) : % of run inside hazard polygon
--   New snow loading (0-30 pts) : depth delta / 6in threshold
--   SWE loading      (0-20 pts) : snowpack weight / 3in threshold
--
-- Note on wind: Station 846 has no wind sensor. SWE is used
-- as a proxy — heavy dense snowpack on steep terrain is an
-- independent instability signal.
--
-- To refresh: DROP the view and re-run this CREATE block.
-- ------------------------------------------------------------

DROP VIEW "skiGIS".vw_run_risk_assessment;

CREATE VIEW "skiGIS".vw_run_risk_assessment AS

WITH latest_weather AS (
    SELECT
        snow_depth_in,
        swe_in,
        precip_accum_in,
        capture_time
    FROM "skiGIS".weather_logs
    WHERE station_id = '846'
    ORDER BY capture_time DESC
    LIMIT 1
),

prev_weather AS (
    SELECT
        snow_depth_in
    FROM "skiGIS".weather_logs
    WHERE station_id = '846'
    ORDER BY capture_time DESC
    LIMIT 1 OFFSET 1
),

new_snow AS (
    SELECT
        GREATEST(
            COALESCE(l.snow_depth_in, 0) - COALESCE(p.snow_depth_in, 0),
        0) AS new_snow_approx_in
    FROM latest_weather l
    LEFT JOIN prev_weather p ON true
),

run_hazard AS (
    SELECT
        r.id                                                        AS run_id,
        r.name                                                      AS run_name,
        r."piste:difficulty"                                        AS difficulty,
        r."piste:grooming"                                          AS grooming,
        r.geom                                                      AS geom,
        COUNT(h.hazard_id)                                          AS hazard_zone_count,
        ROUND(
            (ST_Length(ST_Intersection(r.geom, ST_Union(h.geom))::geography)
            / ST_Length(r.geom::geography) * 100)::numeric
        , 1)                                                        AS pct_run_in_hazard,
        ST_Length(r.geom::geography)                                AS run_length_m
    FROM "skiGIS".ski_runs r
    JOIN "skiGIS".potential_hazard_zones h
        ON ST_Intersects(r.geom, h.geom)
    GROUP BY r.id, r.name, r."piste:difficulty", r."piste:grooming", r.geom
)

SELECT
    rh.run_name,
    rh.difficulty,
    rh.grooming,
    rh.hazard_zone_count,
    rh.pct_run_in_hazard,
    ROUND(rh.run_length_m::numeric, 0)          AS run_length_m,
    lw.snow_depth_in,
    lw.swe_in,
    lw.precip_accum_in,
    ns.new_snow_approx_in,
    lw.capture_time                             AS weather_as_of,
    rh.geom,

    ROUND(
          LEAST(rh.pct_run_in_hazard * 0.5, 50)
        + LEAST(COALESCE(ns.new_snow_approx_in, 0) / 6.0 * 30, 30)
        + LEAST(COALESCE(lw.swe_in, 0)            / 3.0 * 20, 20)
    , 1)                                        AS risk_score,

    CASE
        WHEN LEAST(rh.pct_run_in_hazard * 0.5, 50)
           + LEAST(COALESCE(ns.new_snow_approx_in, 0) / 6.0 * 30, 30)
           + LEAST(COALESCE(lw.swe_in, 0)            / 3.0 * 20, 20) >= 70
            THEN 'HIGH'
        WHEN LEAST(rh.pct_run_in_hazard * 0.5, 50)
           + LEAST(COALESCE(ns.new_snow_approx_in, 0) / 6.0 * 30, 30)
           + LEAST(COALESCE(lw.swe_in, 0)            / 3.0 * 20, 20) >= 40
            THEN 'MODERATE'
        ELSE 'LOW'
    END                                         AS risk_tier

FROM run_hazard rh
CROSS JOIN latest_weather lw
CROSS JOIN new_snow ns
ORDER BY risk_score DESC;

