#!/usr/bin/env python3

import argparse
import cx_Oracle
import json
import pytz
import requests
import socket
import sys
import yaml
from loguru import logger
from pathlib import Path

def load_config_profile_yaml(path):
    """Helper function to automatically load and parse a config profile via argparse"""
    with open(path) as config_file:
        return yaml.safe_load(config_file)

def convert_local_date_to_iso(date):
    """Helper function to convert a native DateTime to UTC ISO8601"""
    return date.astimezone(tz=pytz.utc).isoformat()

# noinspection PyBroadException
def datadog_post(api_url, **kwargs):
    """Helper function to send an API POST to Datadog"""
    try:
        print(kwargs)
        response = requests.post(api_url, json=kwargs, headers=datadog_headers)
        response.raise_for_status()
        print(response.text)
    except:
        logger.exception('Datadog API request failed with an exception')
        raise

def datadog_send_event(**kwargs):
    """Helper function to send a dashboard event to Datadog via REST API"""
    datadog_post(f'''{datadog_config['api-endpoint']}/api/v1/events''', **kwargs)

def datadog_send_log_event(**kwargs):
    """Helper function to send a log event to Datadog via REST API"""
    datadog_post(f'''{datadog_config['logs-endpoint']}/v1/input''', **kwargs)

#
# Program entrypoint if run directly from the command line
#
if __name__ == "__main__":
    # Setup command line argument parsing
    parser = argparse.ArgumentParser(
        prog='oradatadog.py',
        description= (
            'Simple Datadog client for Oracle Database environments without DBA/administrative requirements. '
            'Uses a queue table to capture events in the database and delivers to Datadog via HTTP API.'),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument(
        '--config-profile',
        help='Location of secure configuration file with Datadog and Oracle connection info',
        required=True,
        type=load_config_profile_yaml)

    # Parse and validate command line arguments
    args = parser.parse_args()

    # Unpack config
    datadog_config: dict = args.config_profile['datadog']
    logging_config: dict = args.config_profile['logging']
    oracle_config: dict = args.config_profile['oracle']

    # Unpack Datadog config
    datadog_headers = {
        'DD-API-KEY': datadog_config['api-key']
    }

    # Configure logging
    logger.remove()

    # Unpack logging config
    log_file_path: str = logging_config.get('file-path')
    log_file_rotation: str = logging_config.get('file-rotation', '00:00')
    log_file_retention: str = logging_config.get('file-retention', '14 days')
    log_level: str = logging_config.get('level', 'info').upper()
    log_forward_to_datadog: bool = logging_config.get('forward-to-datadog', False)

    # Set up logging to a file if configured
    if log_file_path is not None:
        logger.add(
            Path(log_file_path),
            rotation=log_file_rotation,
            retention=log_file_retention,
            level=log_level)
    else:
        logger.add(sys.stdout, level=log_level)

    # Set up logging program diagnostics if configured
    if log_forward_to_datadog:
        def datadog_forwarder(message):
            # Send diagnostic event
            datadog_send_log_event(
                date=convert_local_date_to_iso(message.record.get('time')),
                ddsource=logging_config.get('datadog-source', 'oradatadog'),
                hostname=socket.gethostname(),
                message=message.record.get('message'),
                service=logging_config.get('datadog-service'),
                status=message.record.get('level').name)

        logger.add(datadog_forwarder, level=log_level)

    # Connect to Oracle database
    oracle = cx_Oracle.connect(
        oracle_config['user'],
        oracle_config['password'],
        oracle_config['connection-string'],
        encoding="UTF-8")
    logger.debug(f'Connected to Oracle database {oracle_config["connection-string"]} as {oracle_config["user"]}')

    # Query for pending events
    with oracle.cursor() as cursor:
        # Execute query
        rows = cursor.execute('select rowid, datadog_lwc_queue.* from datadog_lwc_queue where queue_status = 0')
        logger.info('Executed query to check for pending events')

        # Iterate rows
        for (rowid, timestamp, status, endpoint_type, payload_json_str) in rows:
            logger.debug(f'Processing event {rowid}')

            # Parse event payload
            payload = json.loads(payload_json_str)

            # Select Datadog API method by endpoint type
            if endpoint_type == 'post_event':
                datadog_send_event(**payload)
            elif endpoint_type == 'post_log_event':
                payload['date'] = convert_local_date_to_iso(timestamp)
                datadog_send_log_event(**payload)
            else:
                # Skip unsupported HTTP methods
                logger.debug(f'event {rowid}: Unsupported endpoint type {endpoint_type}')
                continue

            # Update event status in queue table
            with oracle.cursor() as update_cursor:
                update_cursor.execute('update datadog_lwc_queue set queue_status = 1 where rowid = :rid', rid=rowid)
                if not oracle_config.get('ignore-commit', False):
                    oracle.commit()
                logger.trace(f'event {rowid}: Oracle queue update completed successfully')

        logger.info(f'Processed {cursor.rowcount} row(s)')

    # Cleanup
    oracle.close()
    logger.debug('Disconnected from Oracle database')