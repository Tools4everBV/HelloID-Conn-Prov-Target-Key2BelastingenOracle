# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0] - 2026-09-30

### Added

- Marked the Fit For Purpose (FFP) parts, built for the specific requirements of one implementation: revoking all remaining roles and system privileges before `DROP USER` on delete, and the account import without filtering. The README contains an FFP warning and a section listing these parts, and the scripts concerned contain a `FIT FOR PURPOSE (FFP)` note in their header and at the code.
- GitHub workflows to verify the changelog and create a release.
- Full rebuild of the connector to the current HelloID PowerShell V2 script structure (`$actionContext`/`$outputContext`, action messages, audit logs, DryRun support).
- `update.ps1` and `delete.ps1` (both missing from the original connector).
- Account import/reconciliation (`import.ps1`) from `SYS.DBA_USERS`.
- Importable `fieldMapping.json` for username, password, tablespaces and profile.
- Separate `permissions/systemPrivileges` permissiontype for Oracle system privileges (default `CREATE SESSION`), maintained as a fixed list in its `permissions.ps1`/`importPermissions.ps1`.
- Permission entitlement import per permissiontype: `permissions/oracleRoles/importPermissions.ps1` from `SYS.DBA_ROLE_PRIVS` and `permissions/systemPrivileges/importPermissions.ps1` from `SYS.DBA_SYS_PRIVS`, deduplicated for multitenant (CDB) databases and output in batches of 500 account references.
- Governance reconciliation resolutions for Delete and Disable (no person context required).

### Changed

- README restructured to the current Tools4ever connector layout (supported features, requirements, correlation, field mapping, remarks per topic, database objects).
- Permission scripts moved from the repository root (`permissions.ps1`, `grant_permission.ps1`, `revoke_permission.ps1`) to `permissions/oracleRoles/`.
- Retained the `System.Data.OracleClient` provider, because HelloID agent actions run under Windows PowerShell 5.1.
- Permissions moved to the `permissions/oracleRoles/` subfolder structure; all roles from `SYS.DBA_ROLES` (unfiltered) are exposed, and the permission reference only contains `Id`.
- Account creation no longer grants fixed base roles; all roles and privileges are assigned through HelloID permissions.
- Permission and account import filters moved from connector configuration to their owning scripts.
- Grant and revoke execute the statement directly without checking the current assignment first; "not granted" errors on revoke are treated as already revoked.
- Role grants apply `ALTER USER ... DEFAULT ROLE ALL` so all assigned roles are enabled at login.
- Delete determines its actions up front (`RevokeRoles`, `RevokeSystemPrivileges`, `DeleteAccount`), revokes all remaining roles and system privileges (including grants made outside HelloID) before `DROP USER`, only drops the user when all revokes succeeded, and verifies afterwards that the user no longer exists.
- Query and nonquery execution use one `Invoke-OracleQuery` helper, invoked through descriptive splat variables.
- Username/password authentication is optional when Oracle integrated security is configured for the HelloID Agent service account.
- Update uses a normalized, case-insensitive `Compare-Object` comparison and reports `NoChanges` when no updatable fields are mapped.
- Update, enable, disable and delete return the current state in `PreviousData` and the expected post-action state in `Data`.

### Fixed

- Oracle errors are detected via the base exception (`GetBaseException()`), so errors wrapped by PowerShell in a `MethodInvocationException` are resolved as Oracle errors.
- Counts use `Measure-Object` and empty query results are filtered before `ForEach-Object`, so an empty result is no longer counted as one item (e.g. `REVOKE` without role name, `ORA-00990`).
- Empty `outputContext.Data`/`actionContext.Data` (no mapped fields, reconciliation) no longer breaks the `PreviousData`/`Data` selection.

## [1.0.0] - 2021-06-15

### Added

- Initial work-in-progress version with create, enable and disable actions and role permissions, without update/delete actions.
