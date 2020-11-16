-- Filename: datadog.pkg.sql
-- Project : Datadog API Client for Oracle Database 12.2c
-- Copyright (c) Cloudmation LLC
-- License: Apache License, version 2.0. See LICENSE file in GitHub repository
-- https://github.com/cloudmation-llc/oracle-datadog-client
--
-- Description: Functions and procedures that allow Oracle 
-- database programs to interact with Datadog through the HTTPS API.
--
-- https://www.datadoghq.com
-- https://docs.datadoghq.com/api/
--
-- Revision History
-- Date           Author        Reason for Change
-- ----------------------------------------------------------------
-- 19 Aug 2020    mrapczynski   First version

create or replace package &1..datadog as

    -- Constants for API endpoints
    datadog_api_url_post_event constant varchar2(64) := '/api/v1/events';
    datadog_api_url_post_logs constant varchar2(64) := '/v1/input';

    --
    -- Convert a native Oracle date in a UNIX/POSIX timestamp
    -- Source: https://better-coding.com/pl-sql-how-to-convert-date-to-unix-timestamp/
    --
    function To_Unix_Timestamp(pi_date date) return number;

    --
    -- Query and return a value for a key from the DATADOG_SETTINGS table.
    --
    function Get_Setting(pi_key varchar2) return varchar2;

    --
    -- Send a payload to a Datadog API as a POST request
    --
    function Api_Post(
        pi_url_prefix varchar2,
        pi_payload varchar2,
        pi_host_key varchar2 default 'api_host',
        pi_https_host_key varchar2 default 'api_https_host') return varchar2;

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
        pi_tags varchar2 default null);

end datadog;
/

create or replace package body &1..datadog as

    --
    -- Convert a native Oracle date in a UNIX/POSIX timestamp
    -- Source: https://better-coding.com/pl-sql-how-to-convert-date-to-unix-timestamp/
    --
    function To_Unix_Timestamp(pi_date date) return number as
        l_base_date constant date := to_date('1970-01-01', 'YYYY-MM-DD');
        l_seconds_in_day constant number := 24 * 60 * 60;
    begin
        return trunc((pi_date - l_base_date) * l_seconds_in_day);
    end;

    --
    -- Query and return a value for a key from the DATADOG_SETTINGS table.
    --
    function Get_Setting(pi_key varchar2) return varchar2 as
        l_return_value &1..datadog_settings.value%type := null;
    begin
        -- Query DATADOG_SETTINGS by key
        select value into l_return_value from &1..datadog_settings where lower(key) = lower(pi_key);

        -- Return value if found
        return l_return_value;
    exception
        when no_data_found then
            raise_application_error(-20000, 'Setting ''' || pi_key || ''' not found in DATADOG_SETTINGS. Does it exist?');
    end;

    --
    -- Send a payload to a Datadog API as a POST request, and return the response.
    --
    function Api_Post(
        pi_url_prefix varchar2,
        pi_payload varchar2,
        pi_host_key varchar2 default 'api_host',
        pi_https_host_key varchar2 default 'api_https_host') return varchar2 as

        -- Local variables
        http_req utl_http.req;
        http_res utl_http.resp;
        http_res_body varchar2(4096);
        datadog_api_key &1..datadog_settings.value%type;
        datadog_api_url varchar2(128);
        datadog_wallet_dir &1..datadog_settings.value%type;
        datadog_wallet_pwd &1..datadog_settings.value%type;
    begin
        -- Fetch settings
        datadog_api_url := 'https://' || Get_Setting(pi_host_key);
        datadog_api_key := Get_Setting('api_key');
        datadog_wallet_dir := Get_Setting('wallet_path');
        datadog_wallet_pwd := Get_Setting('wallet_password');

        -- Configure UTL_HTTP with SSL wallet
        utl_http.set_wallet(datadog_wallet_dir, datadog_wallet_pwd);

        -- Create up HTTP request
        http_req := utl_http.begin_request(
            url => datadog_api_url || pi_url_prefix,
            method => 'POST',
            http_version => 'HTTP/1.1',
            https_host => Get_Setting(pi_https_host_key));

        -- Add headers
        utl_http.set_header(http_req, 'Content-Type', 'application/json');
        utl_http.set_header(http_req, 'DD-API-KEY', datadog_api_key);
        utl_http.set_header(http_req, 'Transfer-Encoding', 'chunked');

        -- Write event payload
        utl_http.write_text(http_req, pi_payload);

        -- Send request
        http_res := utl_http.get_response(http_req);

        -- Read response
        utl_http.read_text(http_res, http_res_body);

        -- Cleanup HTTP request
        utl_http.end_response(http_res);

        -- Return response to caller
        return http_res_body;
    exception
        when others then
            -- Cleanup HTTP request
            utl_http.end_response(http_res);

            dbms_output.put_line('An error occurred when sending an event to Datadog');
            dbms_output.put_line(dbms_utility.format_error_stack());
            dbms_output.put_line(dbms_utility.format_error_backtrace());

            -- Send the exception up the call stack
            raise;
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
        api_response varchar2(4096);
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

        -- Send request to API
        api_response := Api_Post(
            datadog_api_url_post_event,
            event_payload.stringify);

        -- Dump output for inspection
        dbms_output.put_line('Datadog response => ' || api_response);
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
        pi_tags varchar2 default null) as

        -- Local variables
        event_payload json_object_t := json_object_t();
        api_response varchar2(4096);
    begin
        -- Construct JSON event payload
        event_payload.put('message', pi_message);
        event_payload.put('hostname', pi_host);
        event_payload.put('ddsource', lower(pi_source));
        event_payload.put('service', lower(pi_service));

        if pi_tags is not null then
            event_payload.put('ddtags', pi_tags);
        end if;

        -- event_payload := event_payload || '}';
        dbms_output.put_line('JSON => ' || event_payload.stringify);

        -- Send request to logs-specific API endpoint
        api_response := Api_Post(
            datadog_api_url_post_logs,
            event_payload.stringify,
            'logs_host',
            'logs_https_host');

        -- Dump output for inspection
        dbms_output.put_line('Datadog response => ' || api_response);
    end;

end datadog;
/

create or replace public synonym datadog for &1..datadog
/