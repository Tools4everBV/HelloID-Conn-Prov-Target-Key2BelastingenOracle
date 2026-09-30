# HelloID-Conn-Prov-Target-Key2BelastingenOracle

| :information_source: Information |
|:---|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as the Oracle data source, a service account and the Oracle Client. You might need to sign a contract or agreement with the supplier (Centric) before implementing this connector. Please contact the client's application manager and database administrator to coordinate the connector requirements. |

| :warning: Fit For Purpose (FFP) |
|:---|
| This connector contains **Fit For Purpose (FFP)** parts: parts that were built for the specific requirements of one implementation, of which it is not certain that they are generic or fit the next implementation. Examples are the delete, which first revokes all remaining roles and system privileges before `DROP USER`, and the account import without filtering. These parts are marked with `FIT FOR PURPOSE (FFP)` in the scripts concerned and listed in [Fit For Purpose (FFP)](#fit-for-purpose-ffp). Review them against the requirements of the customer before implementing this connector. |

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/centric-logo.png" width="500">
</p>

| :warning: Warning |
|:---|
| This connector manages **native Oracle database users** directly with `CREATE USER`, `ALTER USER`, `GRANT`, `REVOKE` and `DROP USER`. The Oracle service account therefore needs powerful rights (see [Requirements](#requirements)).<br>- Delete revokes **all** remaining roles and system privileges of the user, including grants made outside HelloID, and then drops the user<br>- `DropCascade` also drops all objects owned by the user<br><br>Read the [Remarks](#remarks) section carefully and test on a non-production database first. |

## Table of contents

- [HelloID-Conn-Prov-Target-Key2BelastingenOracle](#helloid-conn-prov-target-key2belastingenoracle)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account reference](#account-reference)
    - [Permissions](#permissions)
  - [Remarks](#remarks)
    - [Fit For Purpose (FFP)](#fit-for-purpose-ffp)
    - [Combination with the Key2Belastingen connector](#combination-with-the-key2belastingen-connector)
    - [Account creation](#account-creation)
    - [Update behavior](#update-behavior)
    - [Grant and revoke behavior](#grant-and-revoke-behavior)
    - [Permission import](#permission-import)
    - [Account import](#account-import)
    - [Delete behavior](#delete-behavior)
    - [Governance reconciliation resolutions](#governance-reconciliation-resolutions)
    - [Integrated security](#integrated-security)
    - [Query execution](#query-execution)
  - [Development resources](#development-resources)
    - [Database objects](#database-objects)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Key2BelastingenOracle_ is a _target_ connector. Key2 Belastingen (Centric) is a municipal tax application that runs on an Oracle database, where every user authenticates with a **native Oracle database user**. This connector manages that Oracle user and its Oracle roles and system privileges.

This connector does not manage the Key2 Belastingen application account (the `WMS_GEBRCODE` record); that is done by the separate [HelloID-Conn-Prov-Target-Key2Belastingen](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Key2Belastingen) connector, which references the Oracle username created by this connector. See [Combination with the Key2Belastingen connector](#combination-with-the-key2belastingen-connector).

## Supported features

The following features are available:

| Feature | Supported | Remarks |
| ------- | --------- | ------- |
| Account Lifecycle | ✅ | Create, Update (tablespaces/profile), Enable (`ACCOUNT UNLOCK`), Disable (`ACCOUNT LOCK`), Delete (revoke remaining roles and system privileges, then `DROP USER`). [Read more](#delete-behavior) |
| Permissions | ✅ | Two permissiontypes: Oracle roles (`permissions/oracleRoles`) and system privileges (`permissions/systemPrivileges`), granted and revoked with `GRANT`/`REVOKE`. [Read more](#permissions) |
| Resources | ❌ | Not applicable |
| Entitlement Import: Accounts | ✅⚠️ | All users from `SYS.DBA_USERS`, including system and application schemas. [Read more](#account-import) |
| Entitlement Import: Permissions | ✅ | Per permissiontype: assigned roles from `SYS.DBA_ROLE_PRIVS`, assigned system privileges from `SYS.DBA_SYS_PRIVS`. [Read more](#permission-import) |
| Governance Reconciliation Resolutions | ✅ | Delete and Disable; no person context or field mapping required. [Read more](#governance-reconciliation-resolutions) |

## Getting started

### Requirements

Before implementing this connector, ensure the following requirements are met:

**HelloID agent:**
- A HelloID on-premises agent with network access to the Oracle database server (default port `1521`, or `2484` for TCPS)
- Windows PowerShell 5.1 and a compatible (normally 64-bit) Oracle Client installed on the HelloID agent server. The connector uses the .NET Framework `System.Data.OracleClient` provider

**Oracle service account:**
A dedicated Oracle service account (e.g. `SVC_HelloID`) with:
- `CREATE USER`, `ALTER USER` and `DROP USER`
- Direct `SELECT` on `SYS.DBA_USERS` and `SYS.DBA_ROLES`, and on `SYS.DBA_ROLE_PRIVS` and `SYS.DBA_SYS_PRIVS` (permission import and delete)
- Every managed Oracle role, and every system privilege listed in `permissions/systemPrivileges` (default `CREATE SESSION`), granted `WITH ADMIN OPTION`
- The right to revoke roles and system privileges that were granted outside HelloID, for delete: `ADMIN OPTION` on those roles/privileges, or `GRANT ANY ROLE`/`GRANT ANY PRIVILEGE`

| :warning: Warning |
|:---|
| Without the right to revoke grants made outside HelloID, delete fails on the `REVOKE` and the user is **not** dropped. See [Delete behavior](#delete-behavior). |

### Connection settings

The following settings are required to connect to the Oracle database.

| Setting | Description | Mandatory |
| ------- | ----------- | --------- |
| DataSource | Oracle connection string data source, format `[server]:[port]/[service]`. Append `;Integrated Security=yes` to use integrated security. | Yes |
| Username | Oracle service account username. Leave Username and Password empty for integrated security. | No |
| Password | Oracle service account password. Leave Username and Password empty for integrated security. | No |
| DropCascade | Use `DROP USER ... CASCADE` on delete, which also drops all objects owned by the user. When disabled, `DROP USER` fails if the user owns objects. | No |

### Correlation configuration

The correlation configuration is used to specify which properties are used to match an existing account within Oracle to a person in HelloID.

| Setting | Value |
| ------- | ----- |
| Enable correlation | `True` |
| Person correlation field | The field holding the Oracle username, e.g. `Accounts.MicrosoftActiveDirectory.sAMAccountName` (the supplied mapping uses the uppercase `sAMAccountName`) |
| Account correlation field | `USERNAME` |

### Field mapping

The field mapping can be imported by using the `fieldMapping.json` file. The supplied mapping contains:

| Field | Actions | Value |
| ----- | ------- | ----- |
| `USERNAME` | Create | Active Directory `sAMAccountName` in uppercase |
| `PASSWORD` | Create | Random 12-character initial password (not imported) |
| `DEFAULT_TABLESPACE` | Create, Update | `USERS` |
| `TEMPORARY_TABLESPACE` | Create, Update | `TEMP` |
| `PROFILE` | Create, Update | `DEFAULT` |
| `USER_ID` | Read-only | Imported for reconciliation |
| `ACCOUNT_STATUS` | Read-only | Imported to determine the enabled state |

| :memo: Note |
|:---|
| Replace `MicrosoftActiveDirectory` in the `USERNAME` mapping with the system name of the installed Active Directory target system, and confirm the username convention, tablespaces and profile with the database administrator. |

### Account reference

The account reference is the Oracle `USERNAME`.

### Permissions

Roles and system privileges are separate permissiontypes, each with its own `permissions.ps1`, `grantPermission.ps1`, `revokePermission.ps1` and `importPermissions.ps1`. The permission reference only contains `Id` (the role or privilege name).

- **Oracle roles** (`permissions/oracleRoles`): all roles are read from `SYS.DBA_ROLES`, without filtering
- **System privileges** (`permissions/systemPrivileges`): the managed privileges are a fixed list (`$systemPrivileges`, default `CREATE SESSION`) at the top of `permissions.ps1` and `importPermissions.ps1`

| :warning: Warning |
|:---|
| Keep the `$systemPrivileges` list in `permissions.ps1` and `importPermissions.ps1` in sync. A fixed list is used deliberately: `SYSTEM_PRIVILEGE_MAP` contains 200+ privileges, including high-risk ones such as `DROP ANY TABLE`. |

## Remarks

### Fit For Purpose (FFP)

Fit For Purpose (FFP) means that a part was built for the specific requirements and wishes of one customer/implementation, and is not necessarily suitable for the next customer/implementation. The scripts concerned contain a `FIT FOR PURPOSE (FFP)` note in their header and at the code itself.

The following parts are FFP and must be reviewed per implementation:

| Part | Script / file | Review |
| ---- | ------------- | ------ |
| Revoke all remaining grants before `DROP USER` | `delete.ps1` | Instead of only dropping the user, delete first revokes every remaining role and system privilege, including grants made outside HelloID, and only drops the user when all revokes succeeded. This requires extra rights (`GRANT ANY ROLE`/`GRANT ANY PRIVILEGE`). Confirm with the database administrator that this is desired. See [Delete behavior](#delete-behavior). |
| Account import without filtering | `import.ps1` | All users from `SYS.DBA_USERS` are imported, including Oracle-maintained and application schemas. Other implementations may need a `WHERE` clause. See [Account import](#account-import). |
| Username convention, tablespaces and profile | `fieldMapping.json` | The uppercase Active Directory `sAMAccountName`, `USERS`, `TEMP` and `DEFAULT` were chosen for one implementation. Confirm the values with the customer and the database administrator. See [Field mapping](#field-mapping). |

### Combination with the Key2Belastingen connector

- Provisioning order: Active Directory (username), then this connector (Oracle user), then the Key2Belastingen connector (`WMS_GEBRCODE` record referencing the Oracle username)
- When a customer-specific delete stored procedure is used in the Key2Belastingen connector, run that delete **before** this delete, as such a procedure may require the Oracle user to still exist

### Account creation

- The Oracle user is created with `ACCOUNT UNLOCK` and is therefore usable directly after creation
- Account creation only creates the user; all access is assigned through HelloID permissions and Business Rules

### Update behavior

- Update compares `DEFAULT_TABLESPACE`, `TEMPORARY_TABLESPACE` and `PROFILE` with a normalized, case-insensitive `Compare-Object` comparison and only executes `ALTER USER` for changed values
- When none of these fields is mapped for Update, update reports `NoChanges`
- Update, enable, disable and delete populate `outputContext.PreviousData` with the current Oracle state and `outputContext.Data` with the expected post-action state

### Grant and revoke behavior

- Grant and revoke do not query the current assignment first; the `GRANT`/`REVOKE` statement is executed directly. Oracle accepts a repeated `GRANT` without error
- On revoke, `ORA-01951` (role not granted), `ORA-01952` (system privilege not granted) and `ORA-01918` (user does not exist) are treated as already revoked and logged as skipped; all other errors fail the action
- After each successful role grant, the connector executes `ALTER USER <username> DEFAULT ROLE ALL`. This grants no access itself; it ensures all roles granted to the account are enabled automatically at login. System privilege grants do not execute this statement

### Permission import

- Only assignments to Oracle users are imported; grants to other roles are skipped via a join on `SYS.DBA_USERS`
- Account references are the Oracle `USERNAME`, grouped per permission in batches of 500
- Assignments are deduplicated (`SELECT DISTINCT`): in a multitenant (CDB) database the same grant can be listed both as common and as local grant, which HelloID rejects as duplicate entries
- `permissions/systemPrivileges/importPermissions.ps1` requires `SELECT` on `SYS.DBA_SYS_PRIVS`

### Account import

`import.ps1` imports **all** users from `SYS.DBA_USERS`, without filtering; this includes Oracle-maintained schemas (such as `SYS` and `SYSTEM`) and application schemas. The imported fields are the import fields of the field mapping (`PASSWORD` excluded); an account is imported as enabled when `ACCOUNT_STATUS` is `OPEN`.

| :warning: Fit For Purpose (FFP) |
|:---|
| Importing all users without filtering was chosen for one implementation, see [Fit For Purpose (FFP)](#fit-for-purpose-ffp). If only Key2 Belastingen users must be imported, add a `WHERE` clause to the query in `import.ps1` during implementation, for example on a username convention or `ORACLE_MAINTAINED = 'N'` (Oracle 12c and later). |

### Delete behavior

HelloID revokes its managed permissions before delete. Delete then determines its actions in the `determining actions` step and executes them in this order:

1. `RevokeRoles`: when roles remain (from `SYS.DBA_ROLE_PRIVS`), one `REVOKE` statement for all roles
2. `RevokeSystemPrivileges`: when system privileges remain (from `SYS.DBA_SYS_PRIVS`), one `REVOKE` statement for all privileges
3. `DeleteAccount`: `DROP USER` (optionally `CASCADE`), followed by a check that the user no longer exists

When a revoke fails, the action stops and `DROP USER` is not executed. Object privileges are not revoked separately; `DROP USER` removes them. When the user does not exist, delete is skipped.

| :warning: Fit For Purpose (FFP) |
|:---|
| Delete also revokes roles and system privileges that were granted **outside HelloID**, and only drops the user when all revokes succeeded. This was built for the specific requirements of one implementation; confirm with the database administrator that this is desired, or reduce `delete.ps1` to only `DROP USER`. See [Fit For Purpose (FFP)](#fit-for-purpose-ffp). |

### Governance reconciliation resolutions

Delete and Disable (`ACCOUNT LOCK`) can be triggered from governance reconciliation (`$actionContext.ReconciliationOrigin = 'reconciliation'`), where no person context and no field mapping are available. Both actions only use the account reference, so no hardcoded values are needed. When `outputContext.Data` is empty, `USERNAME` and `ACCOUNT_STATUS` are used as output fields.

### Integrated security

When both Username and Password are empty, the DataSource must contain `Integrated Security=yes`; otherwise the action fails with a clear message. This only works when Oracle OS authentication is configured for the Windows account running the HelloID Agent. Configuring only one of Username or Password is rejected.

### Query execution

- Each action builds a descriptive query variable (for example `$queryGetAccount` or `$queryGrantPermission`) and invokes `Invoke-OracleQuery` through a matching splat. SELECT statements use `NonQuery = $false`; mutating statements use `NonQuery = $true`
- For an empty result, `Invoke-OracleQuery` returns a single `$null`; scripts therefore count with `Measure-Object` and filter with `Where-Object { $_ }` before `ForEach-Object`
- Oracle errors are detected via the base exception (`GetBaseException()`) and resolved by `Resolve-OracleError`

## Development resources

### Database objects

The following database objects and statements are used by the connector:

| Object / statement | Used by | Description |
| ------------------ | ------- | ----------- |
| `SYS.DBA_USERS` | All account actions, import, permission import | Look up the Oracle user and its status |
| `SYS.DBA_ROLES` | `permissions/oracleRoles/permissions.ps1` | List all Oracle roles |
| `SYS.DBA_ROLE_PRIVS` | Role permission import, delete | Roles granted to users |
| `SYS.DBA_SYS_PRIVS` | System privilege permission import, delete | System privileges granted to users |
| `CREATE USER` / `ALTER USER` / `DROP USER` | Create, update, enable, disable, delete | Manage the Oracle user |
| `GRANT` / `REVOKE` | Grant, revoke, delete | Manage roles and system privileges |

## Getting help

| :bulb: Tip |
|:---|
| For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages. |

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
