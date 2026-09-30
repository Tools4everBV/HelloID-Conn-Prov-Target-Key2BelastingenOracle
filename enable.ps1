#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-Enable
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
    $databaseOutputFields = @($outputFields | Where-Object { $_ -ne 'PASSWORD' })
    $actionMessage = "querying Oracle user where USERNAME = [$($actionContext.References.Account)]"
    $queryGetAccount = "
    SELECT
        $((@('USERNAME', 'ACCOUNT_STATUS') + $databaseOutputFields | Select-Object -Unique) -join ', ')
    FROM SYS.DBA_USERS
    WHERE USERNAME = '$($actionContext.References.Account)'
    "
    $splatQueryGetAccount = @{
        Connection = $connection
        Query      = $queryGetAccount
        NonQuery   = $false
    }
    $correlatedAccount = Invoke-OracleQuery @splatQueryGetAccount

    $actionMessage = 'determining action'
    if (($correlatedAccount | Measure-Object).Count -eq 1) {
        $outputContext.PreviousData = ($correlatedAccount | Select-Object -Property $outputFields | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        $outputContext.Data = ($correlatedAccount | Select-Object -Property $outputFields | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        if ($outputFields -contains 'ACCOUNT_STATUS') { $outputContext.Data.ACCOUNT_STATUS = 'OPEN' }

        if ($correlatedAccount.ACCOUNT_STATUS -like 'LOCKED*' -or $correlatedAccount.ACCOUNT_STATUS -eq 'EXPIRED & LOCKED') {
            $action = 'EnableAccount'
        }
        else {
            $action = 'NoChanges'
        }
    }
    elseif (($correlatedAccount | Measure-Object).Count -gt 1) {
        $action = 'MultipleFound'
    }
    else {
        $action = 'NotFound'
    }
    Write-Information "Determined action: [$action]"

    switch ($action) {
        'EnableAccount' {
            $actionMessage = "enabling Oracle user [$($actionContext.References.Account)]"
            $queryEnableAccount = "
            ALTER USER $($actionContext.References.Account)
                ACCOUNT UNLOCK
            "
            $splatQueryEnableAccount = @{
                Connection = $connection
                Query      = $queryEnableAccount
                NonQuery   = $true
            }

            if (-not ($actionContext.DryRun -eq $true)) {
                [void](Invoke-OracleQuery @splatQueryEnableAccount)

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'EnableAccount'
                        Message = "Enabled Oracle user [$($actionContext.References.Account)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would enable Oracle user [$($actionContext.References.Account)]"
            }
            break
        }

        'NoChanges' {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped enabling Oracle user [$($actionContext.References.Account)]. Reason: Already enabled."
                    IsError = $false
                })
            break
        }

        'MultipleFound' {
            throw "Multiple Oracle users found with username: [$($actionContext.References.Account)]. Please correct this so the accounts are unique."
        }

        'NotFound' {
            throw "No Oracle user found with username: [$($actionContext.References.Account)]."
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
