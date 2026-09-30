#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-ImportPermissions-SystemPrivileges
# PowerShell V2
#
# FIT FOR PURPOSE (FFP)
# This connector is Fit For Purpose: it was built for the specific requirements of one implementation.
# It is not a fully generic connector and may not fit the next implementation without changes.
# Review this script against the requirements of each implementation. See README.md, section "Fit For Purpose (FFP)".
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
        $adapter = [System.Data.OracleClient.OracleDataAdapter]::new($command)
        $dataSet = [System.Data.DataSet]::new()
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

# Managed system privileges. Keep this list in sync with permissions.ps1.
$systemPrivileges = @(
    'CREATE SESSION'
)

try {
    Write-Information 'Starting import of Oracle system privilege permission entitlements'

    $connectionString = "Data Source=$($actionContext.Configuration.DataSource)"
    $splatNewOracleConnection = @{
        ConnectionString = $connectionString
        Username         = $actionContext.Configuration.Username
        Password         = $actionContext.Configuration.Password
    }
    $actionMessage = 'opening Oracle connection'
    $connection = New-OracleConnection @splatNewOracleConnection

    # Returns the same system privileges as permissions.ps1. Joining on DBA_USERS excludes privileges granted to roles.
    # DISTINCT is required: in a multitenant (CDB) database the same grant can be listed both as common and as local grant.
    $actionMessage = 'querying Oracle system privilege assignments'
    $queryGetPermissionAssignments = "
    SELECT DISTINCT
        SP.PRIVILEGE AS ID,
        SP.GRANTEE AS USERNAME
    FROM SYS.DBA_SYS_PRIVS SP
    INNER JOIN SYS.DBA_USERS U ON U.USERNAME = SP.GRANTEE
    WHERE SP.PRIVILEGE IN ($(($systemPrivileges | ForEach-Object { "'$_'" }) -join ', '))
    ORDER BY ID, USERNAME
    "
    $splatQueryGetPermissionAssignments = @{
        Connection = $connection
        Query      = $queryGetPermissionAssignments
        NonQuery   = $false
    }
    $permissionAssignments = Invoke-OracleQuery @splatQueryGetPermissionAssignments
    Write-Information "Queried Oracle system privilege assignments. Result count: $(($permissionAssignments | Measure-Object).Count)"

    # Output permission entitlements with account references in batches to prevent exceeding maximum limits
    $actionMessage = 'outputting permission entitlements to HelloID (in batches of 500 account references)'
    $permissionGroups = @($permissionAssignments | Group-Object -Property ID)
    Write-Information "Grouped Oracle system privilege assignments per permission. Permission count: $(($permissionGroups | Measure-Object).Count)"

    $batchSize = 500
    $importedPermissionAssignments = 0
    foreach ($permissionGroup in $permissionGroups) {
        $actionMessage = "outputting permission entitlement [$($permissionGroup.Name)]"

        # Shorten DisplayName to max. 100 chars
        $displayName = "$($permissionGroup.Name)"
        $displayName = $displayName.Substring(0, [System.Math]::Min(100, $displayName.Length))

        $accountReferences = @($permissionGroup.Group | ForEach-Object { "$($_.USERNAME)" } | Select-Object -Unique)
        for ($i = 0; $i -lt ($accountReferences | Measure-Object).Count; $i += $batchSize) {
            $accountReferencesBatch = @($accountReferences[$i..([System.Math]::Min($i + $batchSize, ($accountReferences | Measure-Object).Count) - 1)])
            Write-Output @{
                PermissionReference = @{
                    Id = "$($permissionGroup.Name)"
                }
                DisplayName         = $displayName
                AccountReferences   = $accountReferencesBatch
            }
            $importedPermissionAssignments += ($accountReferencesBatch | Measure-Object).Count
        }
    }

    Write-Information "Completed import of Oracle system privilege permission entitlements. Permission count: $(($permissionGroups | Measure-Object).Count). Assignment count: $($importedPermissionAssignments)"
}
catch {
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
    Write-Error $errorMessage
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
