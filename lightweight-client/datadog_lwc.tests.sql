-- Filename: datadog_lwc.tests.sql
-- Project : Datadog Lightweight API Client for Oracle Database 12.2c
--
-- Copyright (c) Cloudmation LLC
-- License: Apache License, version 2.0. See LICENSE file in GitHub repository
-- https://github.com/cloudmation-llc/oracle-datadog-client
--
-- Description: Test cases for the DATADOG_LWC package.
--
-- https://www.datadoghq.com
-- https://docs.datadoghq.com/api/
--
-- Revision History
-- Date           Author        Reason for Change
-- ----------------------------------------------------------------
-- 18 May 2021    mrapczynski   First version

-- Configure SQL*Plus session
set autocommit on;
set feedback on;
set serveroutput on;
set verify off;
set linesize 200;

-- Create an event for the Datadog dashboard
begin
    datadog_lwc.send_event(
        pi_title => 'Test Alert from PL/SQL',
        pi_text => 'Hello world from ' || user || ' on ' || sysdate);
end;
/

-- Create a log event
begin
    datadog_lwc.send_log_message('Sample log message sent from PL/SQL');
end;
/