#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-Permissions-OracleRoles
# PowerShell V2
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

try {
    Write-Information 'Starting import of Oracle role permissions'

    $connectionString = "Data Source=$($actionContext.Configuration.DataSource)"
    $splatNewOracleConnection = @{
        ConnectionString = $connectionString
        Username         = $actionContext.Configuration.Username
        Password         = $actionContext.Configuration.Password
    }
    $actionMessage = 'opening Oracle connection'
    $connection = New-OracleConnection @splatNewOracleConnection

    $actionMessage = 'querying Oracle roles'
    $queryGetPermissions = "
    SELECT
        ROLE AS ID
    FROM SYS.DBA_ROLES
    ORDER BY ID
    "
    $splatQueryGetPermissions = @{
        Connection = $connection
        Query      = $queryGetPermissions
        NonQuery   = $false
    }
    $roles = Invoke-OracleQuery @splatQueryGetPermissions
    Write-Information "Queried Oracle roles. Result count: $(($roles | Measure-Object).Count)"

    $importedPermissions = 0
    foreach ($role in $roles) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = "$($role.ID)"
                Identification = @{
                    Id = "$($role.ID)"
                }
            }
        )
        $importedPermissions++
    }

    Write-Information "Completed import of Oracle role permissions. Result count: $($importedPermissions)"
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
