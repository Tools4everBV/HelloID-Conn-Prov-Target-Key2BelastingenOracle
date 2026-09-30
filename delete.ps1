#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-Delete
# PowerShell V2
#
# FIT FOR PURPOSE (FFP): revoke all remaining roles and system privileges before DROP USER
# Instead of only dropping the user, delete first revokes every remaining role and system privilege, including grants
# made outside HelloID, and only drops the user when all revokes succeeded. This was built for one implementation and
# requires extra rights (GRANT ANY ROLE/GRANT ANY PRIVILEGE). Confirm with the database administrator that this is desired.
# See README.md, section "Fit For Purpose (FFP)".
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function New-OracleConnection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $ConnectionString,

        [Parameter()]
        [string]
        $Username,

        [Parameter()]
        [string]
        $Password
    )
    try {
        $oracleAssembly = [Reflection.Assembly]::LoadWithPartialName('System.Data.OracleClient')
        if ($null -eq $oracleAssembly) {
            throw 'System.Data.OracleClient could not be loaded. Verify that the action runs in Windows PowerShell 5.1 and the Oracle Client matches the PowerShell architecture.'
        }
        if (-not [string]::IsNullOrEmpty($Username) -and -not [string]::IsNullOrEmpty($Password)) {
            $oracleConnectionString = "$ConnectionString;User Id=$Username;Password=$Password;"
        }
        elseif ([string]::IsNullOrEmpty($Username) -and [string]::IsNullOrEmpty($Password)) {
            if ($ConnectionString -notmatch '(?i)(^|;)\s*Integrated Security\s*=\s*(yes|true)\s*(;|$)') {
                throw "Configure both Username and Password, or add 'Integrated Security=yes' to the configured connection string to use the Windows account running the HelloID Agent."
            }
            $oracleConnectionString = $ConnectionString
        }
        else {
            throw "Configure both Username and Password, or leave both empty and add 'Integrated Security=yes' to the configured connection string."
        }
        $connection = [System.Data.OracleClient.OracleConnection]::new($oracleConnectionString)
        $connection.Open()
        Write-Verbose 'Successfully connected to Oracle database'
        Write-Output $connection
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Invoke-OracleQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Data.OracleClient.OracleConnection]
        $Connection,

        [Parameter(Mandatory)]
        [string]
        $Query,

        [Parameter(Mandatory)]
        [bool]
        $NonQuery
    )
    $command = $Connection.CreateCommand()
    $command.CommandText = $Query
    if ($NonQuery) {
        Write-Output $command.ExecuteNonQuery()
    }
    else {
        $adapter = New-Object System.Data.OracleClient.OracleDataAdapter($command)
        $dataSet = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataSet)
        Write-Output ($dataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors)
    }
}

function Resolve-OracleError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $oracleErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if ($ErrorObject.Exception.InnerException) {
            $oracleErrorObj.FriendlyMessage = $ErrorObject.Exception.InnerException.Message
        }
        Write-Output $oracleErrorObj
    }
}
#endregion functions

try {
    $actionMessage = 'verifying account reference'
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }
    $connectionString = "Data Source=$($actionContext.Configuration.DataSource)"
    $splatNewOracleConnection = @{
        ConnectionString = $connectionString
        Username         = $actionContext.Configuration.Username
        Password         = $actionContext.Configuration.Password
    }
    $actionMessage = 'opening Oracle connection'
    $connection = New-OracleConnection @splatNewOracleConnection

    $outputFields = @($outputContext.Data.PSObject.Properties.Name | Where-Object { $_ })
    # Governance reconciliation resolutions run without person context, so no field mapping is available.
    # Delete has no mapped values (REVOKE/DROP USER); only the output fields need a default.
    if ($actionContext.ReconciliationOrigin -eq 'reconciliation' -and ($outputFields | Measure-Object).Count -eq 0) {
        $outputFields = @('USERNAME', 'ACCOUNT_STATUS')
        Write-Information "Reconciliation mode: delete (output fields: $($outputFields -join ', '))"
    }
    $databaseOutputFields = @($outputFields | Where-Object { $_ -ne 'PASSWORD' })
    $actionMessage = "querying Oracle user where USERNAME = [$($actionContext.References.Account)]"
    $queryGetAccount = "
    SELECT
        $((@('USERNAME') + $databaseOutputFields | Select-Object -Unique) -join ', ')
    FROM SYS.DBA_USERS
    WHERE USERNAME = '$($actionContext.References.Account)'
    "
    $splatQueryGetAccount = @{
        Connection = $connection
        Query      = $queryGetAccount
        NonQuery   = $false
    }
    $correlatedAccount = Invoke-OracleQuery @splatQueryGetAccount

    $actionMessage = 'determining actions'
    $actions = [System.Collections.Generic.List[string]]::new()
    if (($correlatedAccount | Measure-Object).Count -eq 1) {
        $outputContext.PreviousData = ($correlatedAccount | Select-Object -Property $outputFields | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        $outputContext.Data = [PSCustomObject]@{}

        # FIT FOR PURPOSE (FFP): revoking all remaining grants before DROP USER was built for one implementation; see the header.
        # HelloID revokes its managed permissions before delete. Delete clears all remaining roles and system privileges,
        # including grants made outside HelloID, before DROP USER. This requires ADMIN OPTION (or GRANT ANY ROLE/GRANT ANY PRIVILEGE)
        # for every role and system privilege the user can have; if a REVOKE fails, DROP USER is not executed.
        # DISTINCT is required: in a multitenant (CDB) database the same grant can be listed both as common and as local grant.
        # Invoke-OracleQuery returns a single $null for an empty result; Where-Object prevents counting it as one (empty) item.
        $actionMessage = "querying remaining roles of Oracle user [$($actionContext.References.Account)]"
        $queryGetAssignedRoles = "
        SELECT DISTINCT
            GRANTED_ROLE
        FROM SYS.DBA_ROLE_PRIVS
        WHERE GRANTEE = '$($actionContext.References.Account)'
        ORDER BY GRANTED_ROLE
        "
        $splatQueryGetAssignedRoles = @{
            Connection = $connection
            Query      = $queryGetAssignedRoles
            NonQuery   = $false
        }
        $assignedRoles = @(Invoke-OracleQuery @splatQueryGetAssignedRoles | Where-Object { $_ } | ForEach-Object { "$($_.GRANTED_ROLE)" })
        Write-Information "Queried remaining roles of Oracle user [$($actionContext.References.Account)]. Result count: $(($assignedRoles | Measure-Object).Count)"

        $actionMessage = "querying remaining system privileges of Oracle user [$($actionContext.References.Account)]"
        $queryGetAssignedSystemPrivileges = "
        SELECT DISTINCT
            PRIVILEGE
        FROM SYS.DBA_SYS_PRIVS
        WHERE GRANTEE = '$($actionContext.References.Account)'
        ORDER BY PRIVILEGE
        "
        $splatQueryGetAssignedSystemPrivileges = @{
            Connection = $connection
            Query      = $queryGetAssignedSystemPrivileges
            NonQuery   = $false
        }
        $assignedSystemPrivileges = @(Invoke-OracleQuery @splatQueryGetAssignedSystemPrivileges | Where-Object { $_ } | ForEach-Object { "$($_.PRIVILEGE)" })
        Write-Information "Queried remaining system privileges of Oracle user [$($actionContext.References.Account)]. Result count: $(($assignedSystemPrivileges | Measure-Object).Count)"

        # The revokes are executed before DROP USER; DROP USER is only reached when all preceding actions succeeded
        if (($assignedRoles | Measure-Object).Count -gt 0) {
            $actions.Add('RevokeRoles')
        }
        if (($assignedSystemPrivileges | Measure-Object).Count -gt 0) {
            $actions.Add('RevokeSystemPrivileges')
        }
        $actions.Add('DeleteAccount')
    }
    elseif (($correlatedAccount | Measure-Object).Count -gt 1) {
        $actions.Add('MultipleFound')
    }
    else {
        $actions.Add('NotFound')
    }
    Write-Information "Determined actions: [$($actions -join ', ')]"

    foreach ($action in $actions) {
        switch ($action) {
            'RevokeRoles' {
                $actionMessage = "revoking roles [$($assignedRoles -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                $queryRevokeRoles = "
                REVOKE $($assignedRoles -join ', ')
                FROM $($actionContext.References.Account)
                "
                $splatQueryRevokeRoles = @{
                    Connection = $connection
                    Query      = $queryRevokeRoles
                    NonQuery   = $true
                }

                if (-not ($actionContext.DryRun -eq $true)) {
                    [void](Invoke-OracleQuery @splatQueryRevokeRoles)

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'DeleteAccount'
                            Message = "Revoked roles [$($assignedRoles -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would revoke roles [$($assignedRoles -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                }
                break
            }

            'RevokeSystemPrivileges' {
                $actionMessage = "revoking system privileges [$($assignedSystemPrivileges -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                $queryRevokeSystemPrivileges = "
                REVOKE $($assignedSystemPrivileges -join ', ')
                FROM $($actionContext.References.Account)
                "
                $splatQueryRevokeSystemPrivileges = @{
                    Connection = $connection
                    Query      = $queryRevokeSystemPrivileges
                    NonQuery   = $true
                }

                if (-not ($actionContext.DryRun -eq $true)) {
                    [void](Invoke-OracleQuery @splatQueryRevokeSystemPrivileges)

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'DeleteAccount'
                            Message = "Revoked system privileges [$($assignedSystemPrivileges -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would revoke system privileges [$($assignedSystemPrivileges -join ', ')] from Oracle user [$($actionContext.References.Account)]"
                }
                break
            }

            'DeleteAccount' {
                $dropCascade = $actionContext.Configuration.DropCascade -eq $true
                $dropCascadeClause = if ($dropCascade) { ' CASCADE' } else { '' }
                $actionMessage = "deleting Oracle user [$($actionContext.References.Account)] (cascade: [$dropCascade])"
                $queryDeleteAccount = "
                DROP USER $($actionContext.References.Account)$dropCascadeClause
                "
                $splatQueryDeleteAccount = @{
                    Connection = $connection
                    Query      = $queryDeleteAccount
                    NonQuery   = $true
                }

                if (-not ($actionContext.DryRun -eq $true)) {
                    [void](Invoke-OracleQuery @splatQueryDeleteAccount)

                    $actionMessage = "verifying deletion of Oracle user [$($actionContext.References.Account)]"
                    $deletedAccount = Invoke-OracleQuery @splatQueryGetAccount
                    if (($deletedAccount | Measure-Object).Count -ne 0) {
                        throw "Delete verification failed: Oracle user [$($actionContext.References.Account)] still exists after DROP USER."
                    }

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'DeleteAccount'
                            Message = "Deleted Oracle user [$($actionContext.References.Account)] (cascade: [$dropCascade]) and verified that it no longer exists"
                            IsError = $false
                        })
                }
                else {
                    Write-Information "[DryRun] Would delete Oracle user [$($actionContext.References.Account)] (cascade: [$dropCascade])"
                }
                break
            }

            'MultipleFound' {
                throw "Multiple Oracle users found with username: [$($actionContext.References.Account)]. Please correct this so the accounts are unique."
            }

            'NotFound' {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'DeleteAccount'
                        Message = "Skipped deleting Oracle user [$($actionContext.References.Account)]. Reason: Account does not exist."
                        IsError = $false
                    })
                break
            }
        }
    }

    $outputContext.Success = $true
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($ex.Exception.GetBaseException().GetType().FullName -eq 'System.Data.OracleClient.OracleException') {
        $errorObj = Resolve-OracleError -ErrorObject $ex
        $warningMessage = "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        $errorMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
    }
    else {
        $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $errorMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    Write-Warning $warningMessage

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    if ($connection -and $connection.State -eq 'Open') {
        $connection.Close()
        Write-Verbose 'Successfully disconnected from Oracle database'
    }
    if ($connection) {
        $connection.Dispose()
    }
}
