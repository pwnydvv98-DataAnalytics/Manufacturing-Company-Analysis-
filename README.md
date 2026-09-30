# 🏭 Yamato Engineering — Enterprise Manufacturing & OEE Analytics Suite

[![SQL](https://img.shields.io/badge/Database-MySQL%20Workbench-blue.svg)](https://www.mysql.com/)
[![Power BI](https://img.shields.io/badge/BI%20Dashboard-Microsoft%20Power%20BI-yellow.svg)](https://powerbi.microsoft.com/)
[![Data Scale](https://img.shields.io/badge/Scale-4.85M%2B%20Records-green.svg)]()
[![Domain](https://img.shields.io/badge/Domain-Smart%20Manufacturing%20%7C%20IoT%20Telemetry-orange.svg)]()

---
## 📌 Executive Summary
This enterprise data analytics project establishes an end-to-end industrial intelligence and predictive maintenance pipeline for **Yamato Engineering Pvt. Ltd.** The suite evaluates **Overall Equipment Effectiveness (OEE)**, **asset reliability (MTTR / MTBF)**, **quality yield & scrap loss**, and **continuous IoT machine telemetry** across 100 industrial assets in 4 manufacturing plants (*Plant Tokyo, Plant Osaka, Plant Nagoya, Plant Fukuoka*).

Processing **4,850,000+ raw records**, this solution bridges data engineering, relational modeling, and business intelligence to move manufacturing decision-making from reactive troubleshooting to predictive asset monitoring.

---
## 🗂️ Repository Architecture
The repository matches the exact local production folder structure and file hierarchy:

```text
yamato-manufacturing-analytics/
│
├── README.md                                          <-- Complete project documentation
│
├── power bi/
│   └── yamato manufacturing.pbix                      <-- 4-Page Executive Power BI Dashboard
│
├── SQL Work/
│   ├── Table Upload & Data Cleaning & Advanced.sql   <-- Staging DDL, cleaning & ETL logic
│   ├── MTTR MTBF.sql                                  <-- Windowed reliability & failure interval metrics
│   ├── Downtime analysis.sql                          <-- 80/20 Pareto loss calculations
│   └── 7day rolling defect rate and quality trend.sql  <-- Rolling quality windows & SPC metrics
│
└── screenshots/
    ├── page1.png                                      <-- Executive OEE Overview
    ├── page2.png                                      <-- Availability & Downtime Analysis
    ├── page3.png                                      <-- Quality & Scrap Analysis
    └── page4.png                                      <-- IoT Telemetry & Predictive Machine Health
```
> Data Storage Note: Due to GitHub's file size limit (the raw CSV files total over 260 MB, and the PBIX contains ~113 MB of imported data), the cleaned production tables and raw source datasets are hosted on Google Drive.
> 🔗 Download Clean Datasets & Raw CSVs (Google Drive Link)
--- 
## 🏗️ Data Architecture & Star Schema Model
The relational model ingests multi-million-row staging tables in MySQL, applies structural validation, and exports an optimized star schema for Power BI:
```text
                  ┌──────────────────┐
                  │   dim_machines   │
                  │   (100 Assets)   │
                  └────────┬─────────┘
                           │ 1:M
         ┌─────────────────┼─────────────────┬─────────────────┐
         │                 │                 │                 │
┌────────▼────────┐┌───────▼────────┐┌───────▼────────┐┌───────▼────────┐
│ fact_production ││ fact_downtime  ││  fact_quality  ││  fact_sensor   │
│ (1.2M Records)  ││ (1.05M Records)││ (1.1M Records) ││ (1.5M Records) │
└────────▲────────┘└───────▲────────┘└───────▲────────┘└───────▲────────┘
         │                 │                 │                 │
         └─────────────────┼─────────────────┴─────────────────┘
                           │ M:1
                  ┌────────┴─────────┐
                  │     dim_date     │
                  │   (Calendar)     │
                  └──────────────────┘
```
## Table Metadata & Sizing
| Table Name | Entity Type | Target Rows | Key Dimensions / Attributes |
|---|---|---|---|
| dim_machines | Dimension | 100 rows | machine_id, plant_name, line_id, machine_type, ideal_cycle_time_sec, install_year |
| fact_production_logs | Fact | 1,200,000 rows | log_id, timestamp, machine_id, shift, planned_runtime_min, actual_runtime_min, target_units, actual_units |
| fact_downtime_events | Fact | 1,050,000 rows | downtime_id, timestamp, machine_id, downtime_category, duration_minutes, operator_id |
| fact_quality_inspections | Fact | 1,100,000 rows | inspection_id, timestamp, machine_id, units_inspected, scrap_count, defect_category, inspector_id |
| fact_sensor_telemetry | Fact | 1,500,000 rows | telemetry_id, timestamp, machine_id, vibration_rms, temperature_c, pressure_psi, is_anomaly_flag |

---
## ⚙️ SQL Data Engineering & Advanced Queries
The SQL codebase in SQL Work/ handles data loading, transformation, and analytical window metrics:
### 1. Table Upload & Data Cleaning & Advanced.sql
 * Runtime Anomaly Clipping: Prevents mathematical anomalies where \text{Actual Runtime} > \text{Planned Runtime} by capping actual runtime to planned limits.
 * Defect Imputation: Normalizes defect categories by imputing 'No Defect' on all zero-scrap rows (scrap_count = 0) to prevent null-handling issues in DAX filters.
 * Timestamp Standardization: Converts raw string timestamps to standard DATETIME formats and derives indexed integer keys (date_key = YYYYMMDD).
### 2. MTTR MTBF.sql
Calculates asset reliability metrics using window functions:
 * MTTR (Mean Time to Repair): Average repair duration during breakdown events.
 * MTBF (Mean Time Between Failures): Operating duration between consecutive failure timestamps using LAG() OVER (PARTITION BY machine_id ORDER BY timestamp).
```text
WITH failure_events AS (
    SELECT 
        machine_id,
        timestamp,
        duration_minutes,
        LAG(timestamp) OVER (
            PARTITION BY machine_id 
            ORDER BY timestamp
        ) AS prev_failure_time
    FROM fact_downtime_events
    WHERE downtime_category IN ('Mechanical Failure', 'Electrical Fault')
)
SELECT 
    f.machine_id,
    COUNT(*) AS total_failures,
    ROUND(AVG(f.duration_minutes), 2) AS mttr_minutes,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, f.prev_failure_time, f.timestamp)), 2) AS mtbf_minutes
FROM failure_events f
WHERE f.prev_failure_time IS NOT NULL
GROUP BY f.machine_id;
```
### 3. Downtime analysis.sql
Applies running analytic sums to establish the 80/20 Pareto frontier across downtime loss categories:
```text
WITH category_losses AS (
    SELECT 
        downtime_category,
        ROUND(SUM(duration_minutes) / 60.0, 2) AS total_lost_hours
    FROM fact_downtime_events
    GROUP BY downtime_category
),
ranked_losses AS (
    SELECT 
        downtime_category,
        total_lost_hours,
        SUM(total_lost_hours) OVER () AS fleet_total_lost_hours,
        SUM(total_lost_hours) OVER (ORDER BY total_lost_hours DESC) AS running_lost_hours
    FROM category_losses
)
SELECT 
    downtime_category,
    total_lost_hours,
    ROUND((total_lost_hours / fleet_total_lost_hours) * 100, 2) AS pct_of_total,
    ROUND((running_lost_hours / fleet_total_lost_hours) * 100, 2) AS cumulative_pct
FROM ranked_losses;
```
### 4. 7day rolling defect rate and quality trend.sql
Constructs 7-day statistical rolling defect averages to evaluate process stability over time:
```text
WITH daily_quality AS (
    SELECT 
        DATE(timestamp) AS inspection_date,
        machine_id,
        SUM(units_inspected) AS daily_inspected,
        SUM(scrap_count) AS daily_scrap
    FROM fact_quality_inspections
    GROUP BY DATE(timestamp), machine_id
)
SELECT 
    inspection_date,
    machine_id,
    daily_scrap,
    daily_inspected,
    ROUND(
        SUM(daily_scrap) OVER (
            PARTITION BY machine_id 
            ORDER BY inspection_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) / 
        NULLIF(
            SUM(daily_inspected) OVER (
                PARTITION BY machine_id 
                ORDER BY inspection_date 
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ), 0
        ), 4
    ) AS rolling_7d_defect_rate
FROM daily_quality;
```
---
## 📊 Power BI Dashboard Suite (Pages 1–4)
### Page 1: Executive OEE Overview
 * Top KPI Cards: Fleet Availability Rate (99.01%), Performance Rate (98.94%), Quality Rate (99.40%), and Overall OEE (97.37%).
 * Visuals:
   * OEE, Availability & Quality Trend vs. Net Units Produced: Dual-axis combo chart tracking monthly production volumes against target efficiency benchmarks.
   * Asset Performance Breakdown Table: Hierarchical matrix drill-down (Plant_Name \rightarrow Line_ID \rightarrow Machine_ID) auditing planned vs. operating minutes and individual OEE contributions.
 * Filter Context: Slicers for Year (2024 / 2025), Month, Plant_Name, Line_ID, and Machine_Type.
### Page 2: Availability & Downtime Analysis
 * Top KPI Cards: Total Downtime Hours (387.11K), Unplanned Breakdown Count (472K), Fleet MTBF (18.88 Hours), and Fleet MTTR (0.37 Hours).
 * Visuals:
   * Downtime Pareto Chart: Dual-axis chart isolating top downtime categories (Tool Changeover, Mechanical Failure, Electrical Fault, Material Starvation, Preventive Maintenance) against the cumulative 80% line.
   * Shift & Day Heatmap Matrix: Identifies breakdown intensity across Day, Evening, and Night shifts by day of the week.
   * Breakdown Frequency vs. Repair Severity (MTTR): Scatter chart mapping breakdown volume against repair duration across equipment families (CNC Lathe, Injection Molding, Stamping Press, Welding Robot).
### Page 3: Quality & Scrap Analysis
 * Top KPI Cards: Total Inspected Units (109M), Total Good Units (109M), Total Scrap Units (660K), and Fleet Scrap Rate (0.60%).
 * Visuals:
   * Scrap Rate Trend vs. Control Limits: Daily scrap tracking plotted against statistical process control limits.
   * Defect Classification Breakdown: Treemap isolating primary scrap drivers (Dimensional Out-of-Spec, Discoloration, Porosity, Surface Scratch, Burr/Flash).
   * Inspector & Machine Audit Matrix: Tracks individual QC inspector variance and machine scrap output.
### Page 4: IoT Telemetry & Predictive Machine Health
 * Top KPI Cards: Critical Anomaly Telemetry Logs (76K), Fleet Avg Operating Pressure (2.10K PSI), Fleet Avg Vibration (1.20 mm/s RMS), and Fleet Avg Motor Temp (69.99°C).
 * Visuals:
   * Sensor Correlation Scatter Plot: Compares Motor Temperature vs. Vibration RMS by machine to highlight outlier assets operating near thermal and mechanical limits.
   * Real-Time Telemetry Drift: Multi-line timeline monitoring temperature, vibration, and pressure trajectories for individual selected assets.
   * Asset Health Watchlist Table: Dynamic priority matrix categorizing machine condition into CRITICAL ALERT (\ge 815 anomalies), WARNING: MONITOR (\ge 805 anomalies), and NORMAL.
--- 
## 🧮 Core DAX Measures Reference
```dax
-- 1. Operational Availability Rate
Availability Rate = 
DIVIDE(
    SUM(fact_production_logs[actual_runtime_min]),
    SUM(fact_production_logs[planned_runtime_min]),
    0
)

-- 2. Performance Rate
Performance Rate = 
DIVIDE(
    SUM(fact_production_logs[actual_units]),
    SUM(fact_production_logs[target_units]),
    0
)

-- 3. Quality Yield Rate
Quality Rate = 
DIVIDE(
    SUM(fact_quality_inspections[good_units]),
    SUM(fact_quality_inspections[units_inspected]),
    0
)

-- 4. Overall Equipment Effectiveness (OEE)
Overall OEE % = [Availability Rate] * [Performance Rate] * [Quality Rate]

-- 5. Pareto Cumulative Percentage
Cumulative Downtime % = 
VAR TotalDowntime = 
    CALCULATE(
        SUM(fact_downtime_events[duration_hours]), 
        ALLSELECTED(fact_downtime_events[downtime_category])
    )
VAR CurrentCategoryHours = SUM(fact_downtime_events[duration_hours])
VAR CumulativeHours = 
    CALCULATE(
        SUM(fact_downtime_events[duration_hours]),
        FILTER(
            ALLSELECTED(fact_downtime_events[downtime_category]),
            SUM(fact_downtime_events[duration_hours]) >= CurrentCategoryHours
        )
    )
RETURN
    DIVIDE(CumulativeHours, TotalDowntime, 0)

-- 6. Predictive Asset Health Status
Asset Health Status = 
VAR Anomalies = [Anomalous Telemetry Logs]
RETURN
    SWITCH(
        TRUE(),
        Anomalies >= 815, "CRITICAL ALERT",
        Anomalies >= 805, "WARNING: MONITOR",
        "NORMAL"
    )

-- 7. Conditional Formatting Color Palette
Asset Health Status Color = 
SWITCH(
    [Asset Health Status],
    "CRITICAL ALERT", "#D32F2F",   -- Red
    "WARNING: MONITOR", "#FBC02D", -- Amber / Yellow
    "#388E3C"                      -- Green
)
```
---
## 💡 Key Business Insights
* **Downtime Concentration:** Tool changeovers and mechanical breakdowns represent the largest share of lost production hours, demonstrating that implementing SMED (Single-Minute Exchange of Die) methodologies offers the highest ROI for capacity recovery.
* **Predictive Intervention:** Multi-sensor anomaly detection identified high-risk assets (such as MCH-0086 and MCH-0085) running with persistent temperature and vibration anomalies, enabling preventative service before catastrophic motor or bearing seizure.
* **Quality Stability:** Dimensional out-of-spec defects account for the primary share of scrapped parts, isolated primarily to specific tooling setups identified in the inspector audit matrix.
---
## 💻 How to Run Locally
* **Clone the repository:**
   git clone [https://github.com/pwnydvv98-DataAnalytics/yamato-manufacturing-analytics.git]

* Download the datasets from the Google Drive Link provided in this README and save them to your local directory.
* Open MySQL Workbench and execute the scripts inside the SQL Work/ directory in sequence.
* Open power bi/yamato manufacturing.pbix in Microsoft Power BI Desktop to view the interactive dashboard suite.

