-- ============================================================
-- skiGIS | 01_schema_setup.sql
-- ============================================================
-- Purpose : One-time setup script. Creates all tables, indexes,
--           and constraints for the skiGIS schema.
-- Run once : Do not re-run unless rebuilding from scratch.
-- Author   : skiGIS Project
-- ============================================================


-- ------------------------------------------------------------
-- SECTION 1 — Schema
-- ------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS "skiGIS";


-- ------------------------------------------------------------
-- SECTION 2 — Static GIS Tables
-- (Populated via QGIS / ArcGIS Pro import)
-- ------------------------------------------------------------

-- Ski runs pulled from OpenStreetMap
CREATE TABLE "skiGIS".ski_runs (
    gid          SERIAL PRIMARY KEY,
    run_name     VARCHAR(100),
    difficulty   VARCHAR(50),
    geom         GEOMETRY(LineString, 4326)
);

-- Slope-derived avalanche hazard polygons (30-45 degree slopes, binary = 1)
-- Source: Raster slope analysis, converted to vector via ST_Dump
CREATE TABLE "skiGIS".potential_hazard_zones (
    hazard_id    SERIAL PRIMARY KEY,
    geom         GEOMETRY(Polygon, 4326)
);

-- Raw hazard raster-to-vector dump (intermediate — do not use for analysis)
-- potential_hazard_zones is the cleaned version derived from this table
CREATE TABLE "skiGIS".mammoth_hazards_raw (
    gid          SERIAL PRIMARY KEY,
    geom         GEOMETRY(MultiPolygon, 4326)
);


-- ------------------------------------------------------------
-- SECTION 3 — Weather Logs Table
-- (Populated via Python / SNOTEL AWDB API ingest)
-- ------------------------------------------------------------

CREATE TABLE "skiGIS".weather_logs (
    log_id          SERIAL PRIMARY KEY,
    station_id      VARCHAR(50)   NOT NULL,
    capture_time    TIMESTAMP     NOT NULL,
    snow_depth_in   NUMERIC,
    swe_in          NUMERIC,
    temp_avg_f      NUMERIC,
    temp_max_f      NUMERIC,
    temp_min_f      NUMERIC,
    precip_accum_in NUMERIC,
    -- Legacy columns retained for schema continuity
    new_snow_in     NUMERIC(5,2),
    wind_speed_mph  NUMERIC(5,2),
    wind_dir_deg    INT
);


-- ------------------------------------------------------------
-- SECTION 4 — Constraints
-- ------------------------------------------------------------

-- Prevent duplicate ingest rows if pipeline runs more than once per hour
ALTER TABLE "skiGIS".weather_logs
ADD CONSTRAINT uq_weather_logs_station_time
UNIQUE (station_id, capture_time);


-- ------------------------------------------------------------
-- SECTION 5 — Spatial Indexes
-- (Speeds up ST_Intersects and other spatial joins significantly)
-- ------------------------------------------------------------

CREATE INDEX ski_runs_geom_idx
ON "skiGIS".ski_runs USING GIST (geom);

CREATE INDEX potential_hazard_zones_geom_idx
ON "skiGIS".potential_hazard_zones USING GIST (geom);


-- ------------------------------------------------------------
-- SECTION 6 — Populate Hazard Zones from Raw Table
-- Reprojects from EPSG:26911 (UTM) → EPSG:4326 (WGS84)
-- and explodes MultiPolygon → individual Polygons via ST_Dump
-- ------------------------------------------------------------

INSERT INTO "skiGIS".potential_hazard_zones (geom)
SELECT (ST_Dump(ST_Transform(ST_SetSRID(geom, 26911), 4326))).geom
FROM "skiGIS".mammoth_hazards_raw;


-- ------------------------------------------------------------
-- SECTION 7 — Geometry Validation & Repair
-- Self-intersections are common in raster-to-vector conversion.
-- ST_MakeValid fixes them without meaningfully altering shape.
-- ------------------------------------------------------------

UPDATE "skiGIS".potential_hazard_zones
SET geom = ST_MakeValid(geom)
WHERE NOT ST_IsValid(geom);

-- Verify repair worked — should return 0
SELECT COUNT(*)
FROM "skiGIS".potential_hazard_zones
WHERE NOT ST_IsValid(geom);
