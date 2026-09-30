create database manufacturing_analytics;
use manufacturing_analytics;

--- Table Create

-- 1. Staging Machine
create table machine_raw (
Machine_ID varchar(50),
Plant_Name varchar(100),
Line_ID varchar(50),
Machine_Type varchar(100),
Ideal_Cycle_Time_Sec int,
Install_Year int);

--- 2. Staging Production Logs
create table production_logs_raw (
Log_ID int,
Timestamp varchar(50),
Machine_ID varchar(50),
Shift varchar(50),
Planned_Runtime_Min int,
Actual_Runtime_Min int,
Target_Units int,
Actual_Units int);

-- 3. Staging Downtime events
create table downtime_events_raw (
Downtime_ID int,
Timestamp varchar(50),
Machine_ID varchar(50),
Downtime_Category varchar(100),
Duration_minutes int,
Operator_ID varchar(50));

--- 4. staging Quality Inspections
create table quality_inspections_raw (
Inspection_ID int,
Timestamp varchar(50),
Machine_ID varchar(50),
Units_Inspected int,
Scrap_Count int,
Defect_Category varchar(100),
Inspector_ID varchar(50));

--- 5. staging Sensor Telemetry
create table sensor_telemetry_raw (
Telemetry_ID int,
Timestamp varchar(50),
Machine_ID varchar(50),
Vibration_Rms Decimal(6,3),
Temperature_C decimal(6,2),
Pressure_Psi decimal(7,1));

--- 2 Load Csv File
set global local_infile = 1;

--- load Machine CSV
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/manufacturing/raw_machines.csv"
into table machine_raw
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

--- load production_logs csv
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/manufacturing/raw_production_logs.csv"
into table production_logs_raw
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

--- load downtime event csv
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/manufacturing/raw_downtime_events.csv"
into table downtime_events_raw
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

--- load quality_inspections csv
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/manufacturing/raw_quality_inspections.csv"
into table quality_inspections_raw
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

--- load sensor_telemetry csv
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/manufacturing/raw_sensor_telemetry.csv"
into table sensor_telemetry_raw
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

--- 3 Data Quality Audit Queries
--- 1 check for orphaned machine across staging tables
select distinct p.Machine_ID from production_logs_raw p 
left join machine_raw m 
	on p.Machine_ID = m.Machine_ID
where m.Machine_ID is null;

--- 2 audit runtime logic 
select 
	count(*) as invalid_runtime_count,
    max(Actual_Runtime_Min-Planned_Runtime_Min) as max_overshoot_min
from production_logs_raw
 where Actual_Runtime_Min>Planned_Runtime_Min;
 
 --- 3 audit defect categories when scrap_count = 0 vs >0
 select 
	case when Scrap_Count = 0 then 'Zero_Scrap' else 'Has Scrap'
	end as Scrap_Status,
    Defect_Category,
    count(*) as record_count
from quality_inspections_raw
group by scrap_status,Defect_Category;

--- 4 Check for sensor drift or impossible hardware readings
select 
	min(Vibration_Rms) as min_vib, max(Vibration_Rms) as max_vib,
    min(Temperature_C) as min_temp, max(Temperature_C) as max_temp,
    min(Pressure_Psi) as min_psi, max(Pressure_Psi) as max_psi
from sensor_telemetry_raw;

--- 4 create clean tables
--- Dim Machine
create table dim_machine (
Machine_ID varchar(50) primary key,
Plant_Name varchar(100) not null,
Line_ID varchar(50) not null,
Machine_Type varchar(100) not null,
Ideal_Cycle_Time_Sec int not null,
Install_Year int not null,
index Idx_Line_Plant (Plant_Name,Line_ID));

--- Fact Production Logs
create table Fact_Production_Logs (
Log_ID int primary key,
Timestamp datetime not null,
Date_Key int not null,
Machine_ID varchar(50) not null,
Shift varchar(20) not null,
Planned_Runtime_Min int not null,
Actual_Runtime_Min int not null,
Unplanned_Downtime_Min int not null,
Target_Units int not null,
Actual_Units int not null,
Availability_Ratio decimal(6,4),
Performance_Ratio decimal(6,4),
index Idx_Prod_Date(Date_Key),
index Idx_Prod_Machine(Machine_ID));

--- fact Downtime events
create table Fact_Downtime_Events (
Downtime_ID int primary key,
Timestamp datetime not null,
Date_Key int not null,
Machine_ID varchar(50) not null,
Downtime_Category varchar(100) not null,
Duration_Minutes int not null,
Duration_Hours decimal(6,2) not null,
Operator_ID varchar(50),
index Idx_Down_Date(Date_Key),
index Idx_Down_Machine(Machine_ID));

--- Fact Quality Inspections 
create table Fact_Quality_Inspections (
Inspection_ID int primary key ,
Timestamp datetime not null,
Date_Key int not null,
Machine_ID varchar(50) not null,
Units_Inspected int not null,
Scrap_Count int not null,
Good_Units int not null,
Quality_Yield_Ratio decimal(6,4) not null,
Defect_Category varchar(100) not null,
Inspector_ID varchar(50),
index Idx_Qual_Date (Date_Key),
index Idx_Qual_Machine (Machine_ID),
index Idx_Qual_Defect (Defect_Category));

--- Fact Sensor Telemetry
create table Fact_Sensor_Telemetry (
Telemetry_ID int primary key,
Timestamp datetime not null,
Date_Key int not null,
Machine_ID varchar(50) not null,
Vibration_Rms decimal(6,3) not null,
Temperature_C decimal(6,2) not null,
Pressure_Psi decimal(7,1) not null,
Is_Anomaly_Flag tinyint(1) default 0,
index Idx_Sensor_Date (Date_Key),
index Idx_Sensor_Machine (Machine_ID));

--- 5 Data cleaning inserts
--- insert clean machine data
insert into dim_machine (Machine_ID,Plant_Name,Line_ID,Machine_Type,Ideal_Cycle_Time_Sec,Install_Year)
select distinct 
	trim(Machine_ID),
    trim(Plant_Name),
    trim(Line_ID),
    trim(Machine_Type),
    Ideal_Cycle_Time_Sec,
    Install_Year
from machine_raw
where Machine_ID is not null and Machine_ID != '';

--- insert clean Production data
insert into fact_production_logs (Log_ID,Timestamp,Date_Key,Machine_ID,Shift,Planned_Runtime_Min,Actual_Runtime_Min,
Unplanned_Downtime_Min,Target_Units,Actual_Units,Availability_Ratio,Performance_Ratio)
select 
	Log_ID,
    str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s') as Timestamp,
    cast(date_format(str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),'%Y%m%d')as unsigned) as Date_Key,
    Machine_ID,
    Shift,
    Planned_Runtime_Min,
    case
		when Actual_Runtime_Min > Planned_Runtime_Min then Planned_Runtime_Min
        else Actual_Runtime_Min
	end as Actual_Runtime_Min,
    Planned_Runtime_Min - (
    case
		when Actual_Runtime_Min > Planned_Runtime_Min then Planned_Runtime_Min
        else Actual_Runtime_Min
	end ) as Unplanned_Downtime_Min,
    Target_Units,
    greatest(0,Actual_Units) as Actual_Units,
    round(
		(case when Actual_Runtime_Min > Planned_Runtime_Min then Planned_Runtime_Min else Actual_Runtime_Min end)
        /nullif(Planned_Runtime_Min,0),4) 
	as Availability_Ratio,
    round(greatest (0,Actual_Units)/ nullif (Target_Units,0),4) as Performance_Ratio
from production_logs_raw;

--- insert clean data into Downtime_events
insert into fact_downtime_events (Downtime_ID,Timestamp,Date_Key,Machine_ID,Downtime_Category,Duration_Minutes,Duration_Hours,Operator_ID)
select 
	Downtime_ID,
    str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),
    cast(date_format(str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),'%Y%m%d')as unsigned),
    Machine_ID,
    coalesce(nullif(trim(Downtime_Category),''),'unclassified'),
    Duration_minutes,
    round(Duration_Minutes / 60.0,2),
    Operator_ID
from downtime_events_raw;

--- insert clean data into Quality Inspections
insert into fact_quality_inspections (Inspection_ID,Timestamp,Date_Key,Machine_ID,Units_Inspected,Scrap_Count,Good_Units,
Quality_Yield_Ratio,Defect_Category,Inspector_ID)
select 
	Inspection_ID,
    str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),
    cast(date_format(Str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),'%Y%m%d') as unsigned),
    Machine_ID,
    Units_Inspected,
    Scrap_Count,
    (Units_Inspected - Scrap_Count) as Good_Units,
    round((Units_Inspected - Scrap_Count) / nullif(Units_Inspected,0),4) as Quality_Yield_Ratio,
    case
		when Scrap_Count = 0 then 'No Defect'
        when Defect_Category is null  or Defect_Category in ('None','','NaN') then 'Unspecified Defect'
        else trim(Defect_Category)
	end as Defect_Category,
    Inspector_ID
from quality_inspections_raw;

--- insert clean data into Sensor Telemetry
insert into fact_sensor_telemetry(Telemetry_ID,Timestamp,Date_Key,Machine_ID,Vibration_Rms,Temperature_C,Pressure_Psi,Is_Anomaly_Flag)
select 
	Telemetry_ID,
    str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),
    cast(date_format(str_to_date(Timestamp,'%Y-%m-%d %H:%i:%s'),'%Y%m%d')as unsigned),
    Machine_ID,
    Vibration_Rms,
    Temperature_C,
    Pressure_Psi,
    case
		when Temperature_C > 85.0 or Vibration_Rms > 2.0 or Pressure_Psi < 1800.0 then 1
        else 0
	end as Is_Anomaly_Flag
from sensor_telemetry_raw;

--- 6 Executive OEE Summary View
create or replace view vw_machine_oee_summary as 
select 
	m.Machine_ID,
    m.Plant_Name,
    m.Line_ID,
    m.Machine_Type,
    count(distinct p.Log_ID) as total_shifts,
    sum(p.Planned_Runtime_Min) as total_planned_min,
    sum(p.Actual_Runtime_Min) as total_actual_min,
    round(sum(p.Actual_Runtime_Min)/ nullif(sum(p.Planned_Runtime_Min),0),4) as Availability,
    round(sum(p.Actual_Units)/nullif(sum(p.Target_Units),0),4) as Performance ,
    round(sum(q.Good_Units)/nullif(sum(q.Units_Inspected),0),4) as Quality,
    round(
		(sum(p.Actual_Runtime_Min)/ nullif(sum(p.Planned_Runtime_Min),0))*
		(sum(p.Actual_Units)/nullif(sum(p.Target_Units),0))*
        (sum(q.Good_Units)/nullif(sum(q.Units_Inspected),0)),4)
	as Overall_OEE
from dim_machine m 
left join fact_production_logs p 
	on m.Machine_ID = p.Machine_ID
left join fact_quality_inspections q
	on m.Machine_ID  = q.Machine_ID
group by m.Machine_ID,m.Plant_Name,m.Line_ID,m.Machine_Type;

--- 7 Advanced SQL Queries for power bi 
--- 1 
--- MTTR (Mean Time to Repair)
--- MTBF (Mean Time Between Failures)
with failure_events as (
select 
	Machine_ID,
    Timestamp,
    Duration_Minutes,
    lag(Timestamp) over(partition by Machine_ID order by Timestamp) as prev_failure_time
from fact_downtime_events
where Downtime_Category in ('Mechanical Failure','Electrical Fault')),
machine_metrics as (
select 
	f.Machine_ID,
    count(*) as Total_Failures,
    round(avg(f.Duration_Minutes),2) as MTTR_Minutes,
    round(avg(Timestampdiff(minute,f.prev_failure_time,f.Timestamp)),2) as avg_time_between_failure_starts_min
from failure_events f 
where f.prev_failure_time is not null
group by f.Machine_ID)
select
	m.Machine_ID,dm.Plant_Name,dm.Line_ID,dm.Machine_Type,
    m.Total_Failures,m.MTTR_Minutes,m.avg_time_between_failure_starts_min as MTBF_Minutes,
    round(m.MTTR_Minutes/60.0,2) as MTTR_Hours,
    round(m.avg_time_between_failure_starts_min/60.0,2) as MTBF_Hours
from machine_metrics m 
join dim_machine dm 
	on m.Machine_ID = dm.Machine_ID
order by m.Total_Failures desc;

--- 2. 7 day rolling defect rate & quality trend 
with daily_quality as (
select 
	date(Timestamp) as Inspection_Date,
    Machine_ID,
    sum(Units_Inspected) as Daily_Inspected,
    sum(Scrap_Count) as Daily_Scrap 
from fact_quality_inspections
group by date(Timestamp),Machine_ID)
select
	Inspection_Date,
    Machine_ID,
    Daily_Inspected,
    Daily_Scrap,
    round(Daily_Scrap/nullif(Daily_Inspected,0),4) as Daily_Scrap_Rate,
	--- 7 day Rolling window
    sum(Daily_Scrap) over(partition by Machine_ID order by Inspection_Date
    rows between 6 preceding and current row) as Rolling_7d_Scrap,
    --- 7 day rolling defect rate
    round(sum(Daily_Scrap)over(partition by Machine_ID order by Inspection_Date
    rows between 6 preceding and current row)/nullif(sum(Daily_Inspected)over(Partition by Machine_ID order by Inspection_Date
    rows between 6 preceding and current row),0),4) as Rolling_7d_Defect_Rate
from daily_quality
order by Machine_ID,Inspection_Date;

--- 3 Downtime Pareto Analysis
--- Identifies the primary loss category driving factory unreliability
with Category_Losses as (
select 
	Downtime_Category,
    count(*) as Total_Events,
    sum(Duration_Minutes) as Total_Lost_Min,
    round(sum(Duration_Hours),2) as Total_Lost_Hours
from fact_downtime_events
group by Downtime_Category),
Ranked_Losses as (
select
	Downtime_Category,
    Total_Events,
    Total_Lost_Hours,
    sum(Total_Lost_Hours) over() as Fleet_Total_Lost_Hours,
    sum(Total_Lost_Hours) over(order by Total_Lost_Hours desc) as Running_Lost_Hours
from Category_Losses)
select 
	Downtime_Category,
    Total_Events,
    Total_Lost_Hours,
    round((Total_Lost_Hours/Fleet_Total_Lost_Hours)*100,2) as Pct_of_Total_Downtime,
    round((Running_Lost_Hours/Fleet_Total_Lost_Hours)*100,2) as Cumulative_Downtime_Pct
from Ranked_Losses
order by Total_Lost_Hours desc;