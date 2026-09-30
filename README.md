# HelloID-Conn-Prov-Target-Key2BelastingenOracle

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as the Oracle data source, a service account and the Oracle Client. You might need to sign a contract or agreement with the supplier (Centric) before implementing this connector. Please contact the client's application manager and database administrator to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Key2BelastingenOracle/refs/heads/main/Logo.png" width="500">
</p>

> [!WARNING]
> **Fit For Purpose (FFP)**
>
> This connector contains **Fit For Purpose (FFP)** parts: parts that were built for the specific requirements of one implementation, of which it is not certain that they are generic or fit the next implementation. Examples are the delete, which first revokes all remaining roles and system privileges before `DROP USER`, and the account import without filtering. These parts are marked with `FIT FOR PURPOSE (FFP)` in the scripts concerned and listed in [Fit For Purpose (FFP)](#fit-for-purpose-ffp). Review them against the requirements of the customer before implementing this connector.

> [!WARNING]
> This connector manages **native Oracle database users** directly with `CREATE USER`, `ALTER USER`, `GRANT`, `REVOKE` and `DROP USER`. The Oracle service account therefore needs powerful rights (see [Requirements](#requirements)).
>
> - Delete revokes **all** remaining roles and system privileges of the user, including grants made outside HelloID, and then drops the user
> - `DropCascade` also drops all objects owned by the user
>
> Read the [Remarks](#remarks) section carefully and test on a non-production database first.

## Table of contents

- [HelloID-Conn-Prov-Target-Key2BelastingenOracle](#helloid-conn-prov-target-key2belastingenoracle)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account reference](#account-reference)
    - [Permissions](#permissions)
  - [Remarks](#remarks)
    - [Fit For Purpose (FFP)](#fit-for-purpose-ffp)
    - [Not implemented (possible extensions)](#not-implemented-possible-extensions)
    - [Password handling](#password-handling)
    - [Combination with the Key2Belastingen connector](#combination-with-the-key2belastingen-connector)
    - [Account creation](#account-creation)
    - [Update behavior](#update-behavior)
    - [Enable and disable behavior](#enable-and-disable-behavior)
    - [Grant and revoke behavior](#grant-and-revoke-behavior)
    - [Permission import](#permission-import)
    - [Account import](#account-import)
    - [Delete behavior](#delete-behavior)
    - [Governance reconciliation resolutions](#governance-reconciliation-resolutions)
    - [Integrated security](#integrated-security)
    - [Query execution](#query-execution)
    - [Common Oracle errors](#common-oracle-errors)
  - [Development resources](#development-resources)
    - [Database objects](#database-objects)
    - [Oracle documentation](#oracle-documentation)
    - [Script conventions](#script-conventions)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Key2BelastingenOracle_ is a _target_ connector. Key2 Belastingen (Centric) is a municipal tax application that runs on an Oracle database, where every user authenticates with a **native Oracle database user**. This connector manages that Oracle user and its Oracle roles and system privileges.

This connector does not manage the Key2 Belastingen application account (the `WMS_GEBRCODE` record); that is done by the separate [HelloID-Conn-Prov-Target-Key2Belastingen](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Key2Belastingen) connector, which references the Oracle username created by this connector. See [Combination with the Key2Belastingen connector](#combination-with-the-key2belastingen-connector).

## Supported features

The following features are available:

✅ = implemented, ✅⚠️ = implemented with limitations, ❌ = not implemented. The remarks state whether it is not possible or possible but not built, see [Not implemented (possible extensions)](#not-implemented-possible-extensions).

| Feature | Supported | Actions | Remarks |
| ------- | --------- | ------- | ------- |
| Account Lifecycle | ✅⚠️ | Create, Update, Enable, Disable, Delete | Update only changes tablespaces and profile; the username cannot be changed and the password is only set at create (no password reset, by design). Delete revokes remaining roles and system privileges, then `DROP USER`. [Read more](#update-behavior) |
| Permissions | ✅⚠️ | Retrieve, Grant, Revoke | Oracle roles and a fixed list of system privileges, no object privileges. [Read more](#permissions) |
| Resources | ❌ | - | Not built, but possible (`CREATE ROLE`): roles are created by the database administrator or application supplier. [Read more](#not-implemented-possible-extensions) |
| Entitlement Import: Accounts | ✅⚠️ | - | All users from `SYS.DBA_USERS`, without filtering. [Read more](#account-import) |
| Entitlement Import: Permissions | ✅ | - | Assigned roles and system privileges. [Read more](#permission-import) |
| Governance Reconciliation Resolutions | ✅ | Delete, Disable | No person context or field mapping required. [Read more](#governance-reconciliation-resolutions) |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Key2BelastingenOracle/refs/heads/main/Icon.png
```

### Requirements

Before implementing this connector, ensure the following requirements are met.

**HelloID agent:**

- **Local agent**:<br>
  The connector only works through a local HelloID agent; the cloud agent cannot reach the database or use the Oracle Client.
- The agent needs network access to the Oracle database server (default port `1521`, or `2484` for TCPS)
- Windows PowerShell 5.1 and a compatible Oracle Client installed on the HelloID agent server. The connector uses the .NET Framework `System.Data.OracleClient` provider, which is part of Windows PowerShell 5.1 (not PowerShell 7) and is deprecated by Microsoft, but is the only option that works in the HelloID agent actions
- The architecture of the Oracle Client (32-bit or 64-bit) must match the architecture of the PowerShell process of the agent (normally 64-bit)

**Oracle service account:**

Use a dedicated Oracle service account (e.g. `SVC_HelloID`) and grant only the rights below. The table lists per right which connector actions need it, so rights can be left out when an action is not used.

| Right | Required for | Remarks |
| ----- | ------------ | ------- |
| `CREATE SESSION` | All actions | The service account must be able to log in. When `CREATE SESSION` is also managed as system privilege (default), grant it `WITH ADMIN OPTION`, which covers both |
| `CREATE USER` | Create | |
| `ALTER USER` | Update, enable, disable, grant role | Grant role executes `ALTER USER ... DEFAULT ROLE ALL`. Note that `ALTER USER` also allows changing the password of any other Oracle user |
| `DROP USER` | Delete | Also allows dropping any other Oracle user, including their objects when `DropCascade` is enabled |
| `SELECT` on `SYS.DBA_USERS` | Create (correlation and verification), update, enable, disable, delete, account import, permission import | Must be granted directly |
| `SELECT` on `SYS.DBA_ROLES` | Permissions (roles) | Lists the roles that can be assigned |
| `SELECT` on `SYS.DBA_ROLE_PRIVS` | Permission import (roles), delete | |
| `SELECT` on `SYS.DBA_SYS_PRIVS` | Permission import (system privileges), delete | |
| Every managed role `WITH ADMIN OPTION` | Grant role, revoke role | Alternative: `GRANT ANY ROLE` (allows granting **every** role, including `DBA`) |
| Every managed system privilege `WITH ADMIN OPTION` | Grant system privilege, revoke system privilege | The managed privileges are listed in `permissions/systemPrivileges` (default `CREATE SESSION`). Alternative: `GRANT ANY PRIVILEGE` (allows granting **every** system privilege) |
| `ADMIN OPTION` on, or `GRANT ANY ROLE` / `GRANT ANY PRIVILEGE` for, **every** role and system privilege a user may hold | Delete | Delete also revokes grants made outside HelloID ([FFP](#fit-for-purpose-ffp)). Not required when `delete.ps1` is reduced to only `DROP USER` |

Example of the grants for a service account that manages users, the role `KEY2_ROLE` and the default system privilege. Adjust to the roles and privileges in scope:

```sql
GRANT CREATE SESSION TO SVC_HELLOID WITH ADMIN OPTION;
GRANT CREATE USER, ALTER USER, DROP USER TO SVC_HELLOID;
GRANT SELECT ON SYS.DBA_USERS TO SVC_HELLOID;
GRANT SELECT ON SYS.DBA_ROLES TO SVC_HELLOID;
GRANT SELECT ON SYS.DBA_ROLE_PRIVS TO SVC_HELLOID;
GRANT SELECT ON SYS.DBA_SYS_PRIVS TO SVC_HELLOID;
GRANT KEY2_ROLE TO SVC_HELLOID WITH ADMIN OPTION;
```

> [!WARNING]
> - Without the right to revoke grants made outside HelloID, delete fails on the `REVOKE` and the user is **not** dropped. See [Delete behavior](#delete-behavior)
> - When a role or system privilege is assigned to a person in HelloID but the service account has no `ADMIN OPTION` (or `GRANT ANY ...`) on it, Oracle rejects the grant and the action fails
> - The service account needs no rights on the Key2 Belastingen schema or its objects

**Oracle database and naming:**

- Oracle 12c or later is assumed. In a multitenant (CDB) database, connect to the service (PDB) that contains the Key2 Belastingen users; in the root container Oracle only allows common users with the `C##` prefix
- The username must be a valid Oracle identifier without quotes: a letter followed by letters, digits, `_`, `$` or `#`, and within the maximum length of the database (30 bytes, 128 from Oracle 12.2). Oracle stores it in uppercase
- The tablespaces and profile in the field mapping must exist
- The password must satisfy the password verify function of the profile, when one is configured, and may not contain a double quote (`"`)

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

> [!NOTE]
> Replace `MicrosoftActiveDirectory` in the `USERNAME` mapping with the system name of the installed Active Directory target system, and confirm the username convention, tablespaces and profile with the database administrator.

### Account reference

The account reference is the Oracle `USERNAME`.

### Permissions

Roles and system privileges are separate permissiontypes, each with its own `permissions.ps1`, `grantPermission.ps1`, `revokePermission.ps1` and `importPermissions.ps1`. The permission reference only contains `Id` (the role or privilege name).

- **Oracle roles** (`permissions/oracleRoles`): all roles are read from `SYS.DBA_ROLES`, without filtering
- **System privileges** (`permissions/systemPrivileges`): the managed privileges are a fixed list (`$systemPrivileges`, default `CREATE SESSION`) at the top of `permissions.ps1` and `importPermissions.ps1`

> [!WARNING]
> Keep the `$systemPrivileges` list in `permissions.ps1` and `importPermissions.ps1` in sync. A fixed list is used deliberately: `SYSTEM_PRIVILEGE_MAP` contains 200+ privileges, including high-risk ones such as `DROP ANY TABLE`.

## Remarks

### Fit For Purpose (FFP)

Fit For Purpose (FFP) means that a part was built for the specific requirements and wishes of one customer/implementation, and is not necessarily suitable for the next customer/implementation. The scripts concerned contain a `FIT FOR PURPOSE (FFP)` note in their header and at the code itself.

The following parts are FFP and must be reviewed per implementation:

| Part | Script / file | Review |
| ---- | ------------- | ------ |
| Revoke all remaining grants before `DROP USER` | `delete.ps1` | Instead of only dropping the user, delete first revokes every remaining role and system privilege, including grants made outside HelloID, and only drops the user when all revokes succeeded. This requires extra rights (`GRANT ANY ROLE`/`GRANT ANY PRIVILEGE`). Confirm with the database administrator that this is desired. See [Delete behavior](#delete-behavior). |
| Account import without filtering | `import.ps1` | All users from `SYS.DBA_USERS` are imported, including Oracle-maintained and application schemas. Other implementations may need a `WHERE` clause. See [Account import](#account-import). |
| Username convention, tablespaces and profile | `fieldMapping.json` | The uppercase Active Directory `sAMAccountName`, `USERS`, `TEMP` and `DEFAULT` were chosen for one implementation. Confirm the values with the customer and the database administrator. See [Field mapping](#field-mapping). |

### Not implemented (possible extensions)

The following is possible with Oracle and HelloID, but was not built. A next implementation can add it when needed.

| Not implemented | How | Reason |
| --------------- | --- | ------ |
| Update of other attributes, such as a tablespace `QUOTA` | `ALTER USER` in `update.ps1` and `create.ps1` | Only tablespaces and profile were needed |
| Force a password change at first login | `PASSWORD EXPIRE` at create | See [Password handling](#password-handling) |
| End existing sessions on disable | `ALTER SYSTEM KILL SESSION` | Requires very powerful extra rights |
| Filter the assignable roles | `WHERE` clause in `permissions/oracleRoles/permissions.ps1` | All roles are exposed ([FFP](#fit-for-purpose-ffp)); limit this with `ADMIN OPTION` on only the needed roles |
| More system privileges | Extend the list in `permissions.ps1` and `importPermissions.ps1` | A fixed list was chosen deliberately, because of high-risk privileges such as `DROP ANY TABLE` |
| Object privileges, roles with a password, grants to other roles | Extra scripts | Key2 Belastingen access is based on roles and `CREATE SESSION` |
| Resources (create Oracle roles) | `CREATE ROLE` in a resource script | Roles are created by the database administrator or application supplier; the connector only assigns them |

> [!NOTE]
> The reasons above are derived from the current implementation. Confirm them per implementation with the customer and the database administrator.

### Password handling

- A random initial password is set at create only; HelloID knows it (for example for notifications)
- The connector deliberately does not reset or change passwords afterwards. A password reset by a provisioning connector is not recommended and is in general not done in our connectors; users change their password themselves (or through the password process of the customer)
- The account is not created with `PASSWORD EXPIRE`, so the user is only forced to change the password at first login when the profile demands it
- Unlocking an account never resets an expired password, see [Enable and disable behavior](#enable-and-disable-behavior)

### Combination with the Key2Belastingen connector

- Provisioning order: Active Directory (username), then this connector (Oracle user), then the Key2Belastingen connector (`WMS_GEBRCODE` record referencing the Oracle username)
- When a customer-specific delete stored procedure is used in the Key2Belastingen connector, run that delete **before** this delete, as such a procedure may require the Oracle user to still exist
- Configure this connector as a dependent system of Active Directory and the Key2Belastingen connector as dependent on this connector, so the execution order is guaranteed. See [Dependent systems](https://docs.helloid.com/en/provisioning/target-systems/share-account-fields-between-target-systems/access-shared-target-account-fields.html)
- The account reference of this connector (the Oracle username) is the value the Key2Belastingen connector needs; it can be retrieved from the accounts of this target system

### Account creation

- The Oracle user is created with `ACCOUNT UNLOCK` and is therefore usable directly after creation
- Account creation only creates the user; all access is assigned through HelloID permissions and Business Rules

### Update behavior

- Update compares `DEFAULT_TABLESPACE`, `TEMPORARY_TABLESPACE` and `PROFILE` with a normalized, case-insensitive `Compare-Object` comparison and only executes `ALTER USER` for changed values
- When none of these fields is mapped for Update, update reports `NoChanges`
- The username cannot be changed: Oracle has no rename for users, so a changed username in the source does not lead to an update. Delete and recreate the user instead
- Only these three fields can be updated. To manage more attributes (for example a tablespace `QUOTA`), extend `$updatableFields` and the `ALTER USER` clauses in `update.ps1`, and the `CREATE USER` statement in `create.ps1`
- Update, enable, disable and delete populate `outputContext.PreviousData` with the current Oracle state and `outputContext.Data` with the expected post-action state

### Enable and disable behavior

- Disable executes `ACCOUNT LOCK`, and only when `ACCOUNT_STATUS` is exactly `OPEN`. Enable executes `ACCOUNT UNLOCK`, and only when the status starts with `LOCKED` or is `EXPIRED & LOCKED`. In other cases the action reports `NoChanges`
- An `EXPIRED` or `EXPIRED(GRACE)` account (password expired through the profile) is therefore **not** locked by disable. The status combinations `EXPIRED(GRACE) & LOCKED` and `EXPIRED & LOCKED(TIMED)` are not unlocked by enable
- The account import only marks `OPEN` accounts as enabled, so an expired account is imported as disabled
- Unlocking never resets an expired password; the connector does not change passwords. Check the password lifetime (`PASSWORD_LIFE_TIME`) of the `PROFILE` with the database administrator
- Locking does not end existing sessions; a user that is logged in stays connected until the session ends
- Disable and enable on an account that no longer exists fail, as does update

### Grant and revoke behavior

- Grant and revoke do not query the current assignment first; the `GRANT`/`REVOKE` statement is executed directly. Oracle accepts a repeated `GRANT` without error
- On revoke, `ORA-01951` (role not granted), `ORA-01952` (system privilege not granted) and `ORA-01918` (user does not exist) are treated as already revoked and logged as skipped; all other errors fail the action
- After each successful role grant, the connector executes `ALTER USER <username> DEFAULT ROLE ALL`. This grants no access itself; it ensures all roles granted to the account are enabled automatically at login. System privilege grants do not execute this statement

### Permission import

- Only assignments to Oracle users are imported; grants to other roles are skipped via a join on `SYS.DBA_USERS`
- Account references are the Oracle `USERNAME`, grouped per permission in batches of 500
- Assignments are deduplicated (`SELECT DISTINCT`): in a multitenant (CDB) database the same grant can be listed both as common and as local grant, which HelloID rejects as duplicate entries

### Account import

`import.ps1` imports **all** users from `SYS.DBA_USERS`, without filtering; this includes Oracle-maintained schemas (such as `SYS` and `SYSTEM`) and application schemas. The imported fields are the import fields of the field mapping (`PASSWORD` excluded); an account is imported as enabled when `ACCOUNT_STATUS` is `OPEN`, see [Enable and disable behavior](#enable-and-disable-behavior).

> [!WARNING]
> **Fit For Purpose (FFP)**
>
> Importing all users without filtering was chosen for one implementation, see [Fit For Purpose (FFP)](#fit-for-purpose-ffp). If only Key2 Belastingen users must be imported, add a `WHERE` clause to the query in `import.ps1` during implementation, for example on a username convention or `ORACLE_MAINTAINED = 'N'` (Oracle 12c and later).

### Delete behavior

HelloID revokes its managed permissions before delete. Delete then determines its actions in the `determining actions` step and executes them in this order:

1. `RevokeRoles`: when roles remain (from `SYS.DBA_ROLE_PRIVS`), one `REVOKE` statement for all roles
2. `RevokeSystemPrivileges`: when system privileges remain (from `SYS.DBA_SYS_PRIVS`), one `REVOKE` statement for all privileges
3. `DeleteAccount`: `DROP USER` (optionally `CASCADE`), followed by a check that the user no longer exists

Delete is a hard delete: the Oracle user is dropped, not disabled, so nothing of it remains and it cannot be restored. When a revoke fails, the action stops and `DROP USER` is not executed. Oracle refuses to drop a user with an active session (`ORA-01940`), and without `DropCascade` a user that owns objects (`ORA-01922`); delete then fails and can be retried later. Object privileges are not revoked separately; `DROP USER` removes them. When the user does not exist, delete is skipped. With `DropCascade` also the objects of the user (tables, views) are permanently gone.

> [!WARNING]
> **Fit For Purpose (FFP)**
>
> Delete also revokes roles and system privileges that were granted **outside HelloID**, and only drops the user when all revokes succeeded. This was built for the specific requirements of one implementation; confirm with the database administrator that this is desired, or reduce `delete.ps1` to only `DROP USER`. See [Fit For Purpose (FFP)](#fit-for-purpose-ffp).

### Governance reconciliation resolutions

Delete and Disable (`ACCOUNT LOCK`) can be triggered from governance reconciliation (`$actionContext.ReconciliationOrigin = 'reconciliation'`), where no person context and no field mapping are available. Both actions only use the account reference, so no hardcoded values are needed. When `outputContext.Data` is empty, `USERNAME` and `ACCOUNT_STATUS` are used as output fields.

### Integrated security

When both Username and Password are empty, the DataSource must contain `Integrated Security=yes`; otherwise the action fails with a clear message. This only works when Oracle OS authentication is configured for the Windows account running the HelloID Agent. Configuring only one of Username or Password is rejected.

### Query execution

- Statements are built as text, because Oracle DDL (`CREATE USER`, `GRANT`) does not support bind variables for identifiers. The mapped values (`USERNAME`, `DEFAULT_TABLESPACE`, `TEMPORARY_TABLESPACE`, `PROFILE`, `PASSWORD`) are inserted as they are and are not validated or escaped by the connector, so they must come from trusted sources and be valid unquoted Oracle identifiers
- DDL is committed directly by Oracle and cannot be rolled back; a failed action can be partially executed (for example some roles revoked during delete) and the next run continues from the current state
- All actions that change something support DryRun; only the read queries are executed and the changes are logged. Import and the permissions list only read

### Common Oracle errors

| Error | Action | Likely cause |
| ----- | ------ | ------------ |
| `ORA-01031` insufficient privileges | All changing actions | The service account lacks a right from the [Requirements](#requirements) table, for example `ADMIN OPTION` on the role or system privilege |
| `ORA-01920` user name conflicts with another user or role name | Create | The username already exists as a user or role and correlation is disabled or uses another field |
| `ORA-00959` / `ORA-02380` tablespace / profile does not exist | Create, update | The tablespace or profile in the field mapping does not exist in the database |
| `ORA-28003` password verification failed | Create | The generated password does not satisfy the password verify function of the profile |
| `ORA-00988` / `ORA-00911` | Create | The password or username contains a character that is not allowed, such as `"` |
| `ORA-01917` / `ORA-01919` user or role does not exist | Grant | The role does not exist, or the account reference does not exist (anymore) |
| `ORA-01940` cannot drop a user that is currently connected | Delete | The user has an active session. Retry after the session has ended |
| `ORA-01922` CASCADE must be specified to drop a user | Delete | The user owns objects and `DropCascade` is disabled |
| `ORA-12154` / `ORA-12541` | All actions | The `DataSource` cannot be resolved or there is no listener; check the data source, port and network access of the agent |
| `ORA-01045` user lacks `CREATE SESSION` privilege | Login of the created user | The user has no `CREATE SESSION` system privilege; assign it through the `systemPrivileges` permission |

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

### Oracle documentation

- [CREATE USER](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-USER.html)
- [ALTER USER](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-USER.html)
- [DROP USER](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/DROP-USER.html)
- [GRANT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/GRANT.html)
- [REVOKE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/REVOKE.html)
- [DBA_USERS](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DBA_USERS.html)

### Script conventions

- Each action builds a descriptive query variable (for example `$queryGetAccount` or `$queryGrantPermission`) and invokes `Invoke-OracleQuery` through a matching splat. SELECT statements use `NonQuery = $false`; mutating statements use `NonQuery = $true`
- For an empty result, `Invoke-OracleQuery` returns a single `$null`; scripts therefore count with `Measure-Object` and filter with `Where-Object { $_ }` before `ForEach-Object`
- Oracle errors are detected via the base exception (`GetBaseException()`) and resolved by `Resolve-OracleError`

## Getting help

> [!TIP]
> For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
