# skiGIS
A live avalanche hazard tool for Mammoth Mountain that combines real-time SNOTEL snow data with terrain analysis to score and map risk across ski runs. Built with Python, PostgreSQL/PostGIS, and QGIS


# Overview
I wanted to make a tool that helps quantify, measure, and visualize avalanche risk on ski runs using real-time weather data and terrain analysis. Rather than a static map, this is a live pipeline. Every time the ingest script runs, the risk scores update automatically and the QGIS layour reflects the current risk conditions. 

This project gave me hands-on experience connecting a real REST API to a spatial database, writing PostGIS queriers, and building a visualization tool that responds to live data (QGIS). 





## Pipeline Architecture
SNOTEL API (AWDB REST) - 
Python Ingest Script (psycopg2) -
PostgreSQL / PostGIS Database - 
vw_run_risk_assessment (live view) -
QGIS Visualization 



## Tech Stack
| Tool | Purpose |
|---|---|
| Python + psycopg2 | SNOTEL API ingest, DB connection |
| PostgreSQL + PostGIS | Spatial database, geometry operations |
| AWDB REST API | Live SNOTEL weather data (no API key required) |
| OpenStreetMap | Ski run geometries via OSM query |
| ArcGIS Pro | DEM slope analysis, hazard raster classification |
| QGIS | Live DB connection, map visualization |
| DBeaver | Database GUI, query development |

---


## Methodology

### Hazard Zones
A DEM was used to derive a slope raster in ArcGIS Pro. Slopes between 30-45 degrees are recognized to be where 90% of avalanches are released, thus slopes within that range were binary classified as 'hazard terrain' (value = 1). The raster was then converted to polygons and loaded into PostGIS.

### Ski Runs
Ski run geoms were pulled from OpenStreetMap (OSM) and loaded into PostGIS as Linestring features with attributes including name, difficulty, & grooming type.

### Risk Score (0-100)
- Each run is scored using 3 components

| Component | Max Points | Logic |
|---|---|---|
| Terrain Exposure | 50 | % of run length inside a hazard polygon |
| New Snow Loading | 30 | Depth delta between two most recent readings / 6in threshold |
| Snowpack Weight | 20 | SWE / 3in threshold |

Risk Tiers: 
 - HIGH (greater than or equal to 70)
 - MODERATE (greater than or equal to 40)
 - LOW (less than 40)

 ### New Snow Approx (Mammoth)
 Station 846 (Virginia Lakes Ridge) does not have a dedicated new snow sensor. New snow is approximated by calculating the depth delta between the two most recent readings stored in the database. Negative values (mlt/settling) are floored at 0. 

---

## Setup

### Prerequisites
- PostgreSQL with PostGIS extension
- Python 3.x with libraries:
```bash
pip install psycopg2 requests
```
- QGIS 3.x

### DB Setup
1. Create a PostgreSQL database called `gis_portfolio`
2. Enable PostGIS: `CREATE EXTENSION postgis;`
3. Run `sql/01_schema_setup.sql` to create the schema and tables
4. Load ski run and hazard zone shapefiles via PostGIS Shapefile Loader
- Ski runs: export from OSM in EPSG:4326
- Hazard zones: export from ArcGIS Pro slope analysis in EPSG:4326

### Running the pipeline
1. Open `notebook/skiGIS.py` in Jupyter
2. Run all cells top to bottom
3. Enter your PostgreSQL password when prompted
4. Check `sql/03_checks.sql` Check 6 to verify results

### QGIS Visualization
1. Connect QGIS to your PostgreSQL DB via Browser Panel
2. Load `vw_run_risk_assessment` as a PostGIS layer
3. Style by `risk_tier` field — categorized, red/yellow/green
4. Load `mammoth_risk_assessment.qpt` layout template for the full map layout with dynamic conditions panel

## Known Limitations

- **Station distance**: Virginia Lakes Ridge (SNTL 846) is ~30 miles 
north of Mammoth Mountain. No SNOTEL station exists directly at the resort.
- **No wind sensor**: Station 846 does not report wind speed or direction. SWE is used as a proxy for snowpack instability.
- **New snow approximation**: Depth delta method is an estimate, not a direct measurement.
- **Off-season data**: SNOTEL stations report minimal values in late spring/summer. Full risk scoring is most meaningful December through April.

---

## Future Development

- Multi-resort support (Palisades, Kirkwood, Crystal Mt)
- Wind data integration from nearby stations
- Historical risk trending and seasonal analysis
- Web front end for public access

---

## Data Sources

- SNOTEL weather data: NRCS AWDB REST API (wcc.sc.egov.usda.gov)
- Ski run geometries: OpenStreetMap contributors
- Terrain analysis: USGS 3DEP Digital Elevation Model

---

*Built as a GIS portfolio project demonstrating spatial database 
design, REST API integration, and PostGIS analysis.*