# Datadog Client for Oracle Database

## Contents

- [Datadog Client for Oracle Database](#datadog-client-for-oracle-database)
  - [Introduction](#introduction)
    - [Supported API Actions](#supported-api-actions)
  - [Examples](#examples)
  - [Getting Started](#getting-started)
    - [Requirements](#requirements)
    - [Strongly Recommended](#strongly-recommended)
  - [Installation](#installation)
    - [The "Easy Way" (using Ansible)](#the-easy-way-using-ansible)
    - [The Manual Way](#the-manual-way)
  - [Applying Updates](#applying-updates)
    - [Using Ansible Tags](#using-ansible-tags)
      - [Update DATADOG_SETTINGS table from settings file](#update-datadog_settings-table-from-settings-file)
      - [Recompile PL/SQL Package](#recompile-plsql-package)
      - [Generate New Oracle Wallet](#generate-new-oracle-wallet)
      - [Update Network ACEs](#update-network-aces)
  - [Uninstall](#uninstall)

## Introduction

It is common that organizations using the [Oracle Database](https://www.oracle.com/database/) for business software and ERPs will have both data *and* application code coexisting together. Oracle allows for sophisticated business programming using stored procedures written in the PL/SQL language. The *Datadog Client* provides a means for applications designed for the Oracle Database to send events and log messages to [Datadog](https://www.datadoghq.com) for monitoring and analytics.

The common use case is allowing an organization to incorporate monitoring into existing business processes and workflows. For example, user A changes sensitive data, and it is desired that a department manager receive a notification as soon as the change is applied.

Previous options have been using UTL_MAIL to send e-mail or recording audit events to a table. Using Datadog provides monitoring superpowers such as being able to send rich notifications to many destinations including e-mail, Slack, webhooks, or numerous other integrations. Events are archived in Datadog and can be researched for investigations, etc. In short, there are lots of benefits.

Learn more about Datadog at https://www.datadoghq.com

### Supported API Actions

* Sending events to the event stream
* Sending log events

Since most of the primitives needed to work with the Datadog API are created at install, it is trivial to expand the use of this package with additional API calls.

## Examples

**Sending an event to the event stream (https://app.datadoghq.com/event/stream):**

```sql
begin
    datadog.send_event(
        pi_title => 'Test Alert from PL/SQL', /* Required */
        pi_text => 'Hello world user=' || user, /* Required */
        pi_alert_type => 'success'); /* Optional */
end;
/
```

See the Datadog API reference for [posting an event](https://docs.datadoghq.com/api/v1/events/#post-an-event) to learn about all of the supported parameters.

**Sending a log event (https://app.datadoghq.com/logs):**

```sql
begin
    datadog.send_log_message('Sample log message sent from PL/SQL');
end;
/
```

See the Datadog API reference for [sending logs](https://docs.datadoghq.com/api/v1/logs/#send-logs) to learn about all of the supported parameters.

## Getting Started

### Requirements

* Oracle Database 12.2c or greater
  * This is a **hard requirement**. This package uses specific provisions for making HTTPS requests and working with a native JSON API that is only available in 12.2c or greater.
  * If support is desired for earlier versions of Oracle, I recommend forking the repo and refactoring.
* An API key for a Datadog account

### Strongly Recommended

The simplest and quickest install method is using the Ansible playbook provided in this repo (`install-datadog.yml`). To use the playbook, the following is needed:

* Ansible
* Python 3.6 or greater
* Command line tools:
  * OpenSSL client (i.e. `openssl s_client ...`)
  * Oracle `sqlplus` and `orapki`

The Ansible playbook was developed against an Oracle 12.2c instance installed on RHEL 7. For most organizations, the above requirements should be easy to meet.

## Installation

Making web service calls from the Oracle Database is not as simple as calling UTL_HTTP, and done. There are also requirements to set up network ACE entries, and provide an Oracle Wallet with only the root certificate. If you do not have a lot of DBA experience, then the steps can be maddening.

### The "Easy Way" (using Ansible)

Using the Ansible playbook allows you to breeze right through all of the steps, and should work for many (if not all) situations.

1. Configuration
   * Each file has comments explaining what is expected for each setting
   * Copy `datadog-install-settings.sample.yml` to `datadog-install-settings.yml`, and customize the values 
   * Copy `datadog-settings.sample.yml` to `datadog-settings.yml`, and customize the values
  
2. Install by running `ansible-playbook install-datadog.yml`

3. Try it out by sending an event. See the examples above for simple calls that work simply by copying and pasting. A public synonym is created automatically at install, but you will need to `grant execute on datadog to ...` in order for database schemas to use it. 

If the installation was successful, you will not receive any SQL errors, and Datadog will return a positive response indicating the event was accepted.

### The Manual Way

If you cannot or do not want to use Ansible, then you can install the Datadog package by following all of the manual steps. At the minimum, it is recommended that you review the `install-datadog.yml` playbook to get an idea for the different steps that need to be executed.

1. Create the DATADOG_SETTINGS table. See the parameterized script for SQL*Plus at `sql-install/create-settings-table.sql`.
   
2. Load the DATADOG_SETTINGS table with records. Follow the `datadog-settings.sample.yml` for what keys to insert, and which values to provide.

3. Compile the DATADOG package. See the parameterized script for SQL*Plus at `datadog.pkg.sql`.

4. Create a new Oracle Wallet, and add the root certificate for Datadog to it. You can extract public certificates using the OpenSSL client on the command line, or some browsers provide a GUI method to view and download certificates (though trying to do this for an API endpoint could be challenging). Do not add intermediate certificates, or the endpoint certificate itself to the wallet. All Oracle wants to see is the root of the certificate chain.

5. Configure the network ACEs that permits the **schema which owns** the DATADOG package to make outbound HTTPS calls to the Datadog API. See the parameterized script for SQL*Plus at `sql-install/create-network-ace.sql`. ACEs do not need to be created for end users who call the packages stored programs.

## Applying Updates

### Using Ansible Tags

The tasks in the Ansible installation playbook are also tagged so that you can re-run specific tasks even after a complete install.

#### Update DATADOG_SETTINGS table from settings file

`ansible-playbook install-datadog.yml --tags update-settings`

#### Recompile PL/SQL Package

`ansible-playbook install-datadog.yml --tags build-plsql`

#### Generate New Oracle Wallet

The Oracle wallet will need to be occasionally rebuilt using updated an root certificate when Datadog renews the certificates for their endpoints. You can fetch the latest certificates on demand and generate new wallet files by running the following:

`ansible-playbook install-datadog.yml --tags build-wallet`

#### Update Network ACEs

`ansible-playbook install-datadog.yml --tags build-network-ace`

## Uninstall

For an easy uninstall, simply run the `uninstall-datadog.yml` playbook, and the objects and network ACEs will be deleted from the database. The wallet with the root certificate *is not deleted*.

A manual uninstall is not much different. Reverse each change step by step until it is gone.