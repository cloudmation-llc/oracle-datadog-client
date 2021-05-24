-- Filename: datadog_lwc.pkg.sql
-- Project : Datadog Lightweight API Client for Oracle Database 12.2c
--
-- Copyright (c) Cloudmation LLC
-- License: Apache License, version 2.0. See LICENSE file in GitHub repository
-- https://github.com/cloudmation-llc/oracle-datadog-client
--
-- Description: Functions and procedures which create a lightweight integration
-- between an Oracle database and Datadog.
--
-- https://www.datadoghq.com
-- https://docs.datadoghq.com/api/
--
-- Revision History
-- Date           Author        Reason for Change
-- ----------------------------------------------------------------
-- 18 May 2021    mrapczynski   First version

-- Configure SQL*Plus session
set feedback on;
set serveroutput on;
set verify off;

-- Check to see if the Datadog queue table should be created
variable queue_table_exists number;
exec select count(*) into :queue_table_exists from all_tables where table_name = 'DATADOG_LWC_QUEUE';
begin
    if :queue_table_exists = 0 then
        dbms_output.enable(90000);
        dbms_output.put_line('install: DATADOG_LWC_QUEUE table not found -- will create');

        execute immediate 'create table &1..datadog_lwc_queue (
            event_timestamp timestamp default systimestamp,
            queue_status number(1) default 0,
            endpoint_type varchar2(32 char) default ''post_event'',
            payload varchar2(2048 char),
            constraint ensure_payload_json check (payload is json))';

        dbms_output.put_line('install: DATADOG_LWC_QUEUE table created successfully');
    else
        dbms_output.put_line('install: DATADOG_LWC_QUEUE already exists -- nothing to do');
    end if;
end;
/

create or replace package &1..datadog_lwc as

    --
    -- Convert a native Oracle date to a UNIX/POSIX timestamp
    -- Source: https://better-coding.com/pl-sql-how-to-convert-date-to-unix-timestamp/
    --
    function To_Unix_Timestamp(pi_date date) return number;

    --
    -- Deliver an event to the Datadog event stream.
    -- See API reference at https://docs.datadoghq.com/api/v1/events/#post-an-event
    --
    procedure Send_Event(
        pi_title varchar2,
        pi_text varchar2,
        pi_aggregation_key varchar2 default null,
        pi_alert_type varchar2 default 'info',
        pi_date_happened date default null,
        pi_device_name varchar2 default null,
        pi_host varchar2 default sys_context('USERENV', 'SERVER_HOST'),
        pi_priority varchar2 default 'normal',
        pi_related_event_id number default null,
        pi_source_type varchar2 default 'datadog',
        pi_tags varchar2 default null);

    --
    -- Deliver a message to Datadog as a log event.
    -- See API reference at https://docs.datadoghq.com/api/v1/logs/#send-logs
    --
    procedure Send_Log_Message(
        pi_message varchar2,
        pi_host varchar2 default sys_context('USERENV', 'SERVER_HOST'),
        pi_source varchar2 default 'oracle',
        pi_service varchar2 default 'database-' || sys_context('USERENV', 'INSTANCE_NAME'),
        pi_tags varchar2 default null,
        pi_status varchar2 default 'info');

end datadog_lwc;
/

create or replace package body &1..datadog_lwc as

    --
    -- Convert a native Oracle date to a UNIX/POSIX timestamp
    -- Source: https://better-coding.com/pl-sql-how-to-convert-date-to-unix-timestamp/
    --
    function To_Unix_Timestamp(pi_date date) return number as
        l_base_date constant date := to_date('1970-01-01', 'YYYY-MM-DD');
        l_seconds_in_day constant number := 24 * 60 * 60;
    begin
        return trunc((pi_date - l_base_date) * l_seconds_in_day);
    end;

    --
    -- Deliver an event to the Datadog event stream.
    -- See API reference at https://docs.datadoghq.com/api/v1/events/#post-an-event
    --
    procedure Send_Event(
        pi_title varchar2,
        pi_text varchar2,
        pi_aggregation_key varchar2 default null,
        pi_alert_type varchar2 default 'info',
        pi_date_happened date default null,
        pi_device_name varchar2 default null,
        pi_host varchar2 default sys_context('USERENV', 'SERVER_HOST'),
        pi_priority varchar2 default 'normal',
        pi_related_event_id number default null,
        pi_source_type varchar2 default 'datadog',
        pi_tags varchar2 default null) as

        -- Local variables
        event_payload json_object_t := json_object_t();
        event_payload_str varchar2(2048 char);
    begin
        -- Construct JSON event payload
        event_payload.put('title', pi_title);
        event_payload.put('text', pi_text);
        event_payload.put('alert_type', pi_alert_type);
        event_payload.put('host', pi_host);
        event_payload.put('priority', pi_priority);
        event_payload.put('source_type_name', pi_source_type);
        event_payload.put('tags', pi_tags);

        if pi_aggregation_key is not null then
            event_payload.put('aggregation_key', pi_aggregation_key);
        end if;

        if pi_date_happened is not null then
            event_payload.put('date_happened', To_Unix_Timestamp(pi_date_happened));
        end if;

        if pi_device_name is not null then
            event_payload.put('device_name', pi_device_name);
        end if;

        if pi_related_event_id is not null then
            event_payload.put('related_event_id', pi_related_event_id);
        end if;

        -- Serialize JSON (needed for SQL interop)
        event_payload_str := event_payload.stringify;

        -- Insert into queue table for processing
        insert into &1..datadog_lwc_queue
        (endpoint_type, payload)
        values ('post_event', event_payload_str);
    end;

    --
    -- Deliver a message to Datadog as a log event.
    -- See API reference at https://docs.datadoghq.com/api/v1/logs/#send-logs
    --
    procedure Send_Log_Message(
        pi_message varchar2,
        pi_host varchar2 default sys_context('USERENV', 'SERVER_HOST'),
        pi_source varchar2 default 'oracle',
        pi_service varchar2 default 'database-' || sys_context('USERENV', 'INSTANCE_NAME'),
        pi_tags varchar2 default null,
        pi_status varchar2 default 'info') as

        -- Local variables
        event_payload json_object_t := json_object_t();
        event_payload_str varchar2(2048 char);
    begin
        -- Construct JSON event payload
        event_payload.put('message', pi_message);
        event_payload.put('hostname', pi_host);
        event_payload.put('ddsource', lower(pi_source));
        event_payload.put('service', lower(pi_service));
        event_payload.put('status', pi_status);

        if pi_tags is not null then
            event_payload.put('ddtags', pi_tags);
        end if;

        -- Serialize JSON (needed for SQL interop)
        event_payload_str := event_payload.stringify;

        -- Insert into queue table for processing
        insert into &1..datadog_lwc_queue
        (endpoint_type, payload)
        values ('post_log_event', event_payload_str);
    end;

end datadog_lwc;
/

create or replace public synonym datadog_lwc for &1..datadog_lwc
/