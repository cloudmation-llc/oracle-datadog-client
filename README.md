# Datadog Client for Oracle Database

## Contents <!-- omit in toc -->

- [Datadog Client for Oracle Database](#datadog-client-for-oracle-database)
  - [Introduction](#introduction)
  - [Native Client](#native-client)
  - [Lightweight Client](#lightweight-client)

## Introduction

This project is a collection of different types of clients for integrating an [Oracle Database](https://www.oracle.com/database/) with [Datadog](https://www.datadoghq.com).

## Native Client

Designed for use when you have administrative/DBA access to your Oracle environment. It leverages the UTL_HTTP PL/SQL package along with supplementary tools such as Oracle Wallet for HTTPS certificates. Provides a real-time _and_ direct integration with Datadog that works in your PL/SQL programs and table triggers.

## Lightweight Client

Designed for access restricted (i.e. managed hosting) Oracle environments where you have a lot of control over tables (data) and the ability to develop some kinds of PL/SQL programs, but do you not have DBA privileges to be able to change the database configuration or use PL/SQL APIs which require administrative permissions.

In this design, API calls to Datadog are queued into a table. An external program on another server fetches the queued records and performs the corresponding API call to Datadog. An example external program is provided that can be scheduled to check the queue table on a regular interval. However there is more than one way to effectively use the queue table model.