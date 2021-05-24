#!/usr/bin/env python3

import argparse
import cx_Oracle
import json
import requests
import sys
import yaml
from loguru import logger
from pathlib import Path

def load_config_profile_yaml(path):
    """Helper function to automatically load and parse a config profile via argparse"""
    with open(path) as config_file:
        return yaml.safe_load(config_file)

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

    parser.add_argument(
        '--log-file',
        help='Set the path to a log file instead of writing to standard out',
        type=Path,
        default=None)

    parser.add_argument(
        '--log-file-rotation',
        help='If logging to a file is enabled, set the rotation frequency',
        default='00:00')

    parser.add_argument(
        '--log-file-retention',
        help='If logging to a file is enabled, set the rotation frequency',
        default='14 days')

    parser.add_argument(
        '--log-level',
        help='Set the log verbosity level',
        default='warning')

    # Parse and validate command line arguments
    args = parser.parse_args()

    # Configure logging
    logger.remove()

    if args.log_file is not None:
        logger.add(
            args.log_file,
            rotation=args.log_file_rotation,
            retention=args.log_file_retention,
            level=args.log_level.upper())
    else:
        logger.add(sys.stdout, level=args.log_level.upper())

    logger.trace('Program arguments %s' % args)

    # Unpack config
    datadog_config = args.config_profile['datadog']
    oracle_config = args.config_profile['oracle']

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
        for (rowid, timestamp, status, endpoint_type, api_url, api_http_method, payload) in rows:
            logger.debug(f'Processing event {rowid}')

            # Select Datadog endpoint
            if endpoint_type == 'log':
                endpoint_url = datadog_config['logs-endpoint']
            else:
                endpoint_url = datadog_config['api-endpoint']
            logger.debug(f'event {rowid}: Using {endpoint_url} for API endpoint')

            # Select HTTP request method
            if api_http_method == 'post':
                http = requests.post
            elif api_http_method == 'put':
                http = requests.put
            else:
                # Skip unsupported HTTP methods
                logger.debug(f'event {rowid}: Unsupported HTTP method {api_http_method}')
                continue

            try:
                # Send Datadog API request
                response = http(
                    url=f'{endpoint_url}{api_url}',
                    json=json.loads(payload),
                    headers={
                        'DD-API-KEY': datadog_config['api-key']
                    })

                # Check for errors
                response.raise_for_status()
                logger.trace(f'event {rowid}: HTTP delivery completed successfully')

                # Update event status in queue table
                with oracle.cursor() as update_cursor:
                    update_cursor.execute('update datadog_lwc_queue set queue_status = 1 where rowid = :rid', rid=rowid)
                    oracle.commit()
                    logger.trace(f'event {rowid}: Oracle queue update completed successfully')

                logger.info(f'event {rowid}: Completed successfully')
            except:
                logger.exception('Datadog API request failed with an exception')

        logger.info(f'Processed {cursor.rowcount} row(s)')

    # Cleanup
    oracle.close()
    logger.debug('Disconnected from Oracle database')