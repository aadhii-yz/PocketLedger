---
title: Admin Guide
description: System logs, user management, and maintenance for administrators.
---

The admin section (`/admin`) is restricted to users with the `admin` role.

## System logs

`/admin/logs` — application-level event log. Every significant operation (bill creation, stock adjustment, transfer completion, errors) writes a log record.

| Field | Notes |
|---|---|
| Level | `INFO` · `WARNING` · `ERROR` |
| Message | What happened |
| Data | JSON payload with context (product ID, quantities, etc.) |
| Created | Timestamp |

Logs older than **90 days** are pruned automatically at startup.

The log table is filterable by level. Use it to:
- Audit who did what and when
- Diagnose errors after the fact
- Track stock adjustments and bill creation

## User management

`/admin/users` — create, edit, and deactivate users. Same interface as the manager view, but admins can also change roles, including granting or revoking `admin` access.

**Changing a `pos` user's shop:** update their `assigned_shop` field. The change takes effect on their next login (the billing page re-reads the shop from the auth record).

## Database access

PocketBase's built-in admin UI is available at `/_/` (e.g. `https://your-app.example.com/_/`). Log in with your superadmin credentials to:
- Browse and edit any collection directly
- Export data as JSON or CSV
- Manage database indexes and access rules
- View PocketBase's built-in request logs

## Pre-delete protection

The system blocks deletion of:
- **Products** that have any stock records — delete the stock entries first
- **Locations** that are referenced by stock, bills, or transfers — resolve references first

This prevents orphaned data and broken foreign keys.

## Startup behaviour

On every server start, PocketLedger:
1. Runs `CreateCollections` — idempotently creates or updates database collections and indexes
2. Seeds default Warehouse and Shop locations if they don't exist
3. Back-fills `location` fields on existing stock records if missing
4. Prunes `system_logs` older than 90 days
