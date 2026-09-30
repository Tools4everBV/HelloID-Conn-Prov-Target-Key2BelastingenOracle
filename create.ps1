#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-Create
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
    $outputContext.AccountReference = 'Currently not available'

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

    $actionMessage = 'validating correlation configuration'
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue.ToUpper()
        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [personFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $actionMessage = "querying account where [$correlationField] = [$correlationValue]"
        $queryCorrelateAccount = "
        SELECT $((@('USERNAME') + $databaseOutputFields | Select-Object -Unique) -join ', ')
        FROM SYS.DBA_USERS
        WHERE $($correlationField) = '$($correlationValue)'
        "
        $splatQueryCorrelateAccount = @{
            Connection = $connection
            Query      = $queryCorrelateAccount
            NonQuery   = $false
        }
        $correlatedAccount = Invoke-OracleQuery @splatQueryCorrelateAccount
        Write-Information "Queried account where [$correlationField] = [$correlationValue]. Result count: $(($correlatedAccount | Measure-Object).Count)"
    }

    $actionMessage = 'determining action'
    if (($correlatedAccount | Measure-Object).Count -eq 0) {
        $action = 'CreateAccount'
    }
    elseif (($correlatedAccount | Measure-Object).Count -eq 1) {
        $action = 'CorrelateAccount'
    }
    else {
        $action = 'MultipleFound'
    }
    Write-Information "Determined action: [$action]"

    switch ($action) {
        'CreateAccount' {
            $actionMessage = "creating account [$($actionContext.Data.USERNAME)]"
            $queryCreateAccount = "
            CREATE USER $($actionContext.Data.USERNAME)
                IDENTIFIED BY `"$($actionContext.Data.PASSWORD)`"
                DEFAULT TABLESPACE $($actionContext.Data.DEFAULT_TABLESPACE)
                TEMPORARY TABLESPACE $($actionContext.Data.TEMPORARY_TABLESPACE)
                PROFILE $($actionContext.Data.PROFILE)
                ACCOUNT UNLOCK
            "
            $splatQueryCreateAccount = @{
                Connection = $connection
                Query      = $queryCreateAccount
                NonQuery   = $true
            }
            if (-not ($actionContext.DryRun -eq $true)) {
                [void](Invoke-OracleQuery @splatQueryCreateAccount)
                $outputContext.AccountReference = $actionContext.Data.USERNAME

                $actionMessage = "querying created Oracle account [$($actionContext.Data.USERNAME)]"
                $queryGetCreatedAccount = "
                SELECT $((@('USERNAME') + $databaseOutputFields | Select-Object -Unique) -join ', ')
                FROM SYS.DBA_USERS
                WHERE USERNAME = '$($actionContext.Data.USERNAME)'
                "
                $splatQueryGetCreatedAccount = @{
                    Connection = $connection
                    Query      = $queryGetCreatedAccount
                    NonQuery   = $false
                }
                $createdAccount = Invoke-OracleQuery @splatQueryGetCreatedAccount
                if (($createdAccount | Measure-Object).Count -ne 1) {
                    throw "Could not retrieve the created Oracle account [$($actionContext.Data.USERNAME)]."
                }
                $outputContext.Data = ($createdAccount | Select-Object -Property $outputFields | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
                if ($outputFields -contains 'PASSWORD') {
                    $outputContext.Data.PASSWORD = $actionContext.Data.PASSWORD
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateAccount'
                        Message = "Created account [$($actionContext.Data.USERNAME)]. AccountReference is: [$($outputContext.AccountReference)]"
                        IsError = $false
                    })
            }
            else {
                Write-Information "[DryRun] Would create account [$($actionContext.Data.USERNAME)]"
            }
            break
        }

        'CorrelateAccount' {
            $actionMessage = "correlating to account on field: [$($correlationField)] with value: [$($correlationValue)]"
            $outputContext.AccountReference = $correlatedAccount.USERNAME
            $outputContext.Data = ($correlatedAccount | Select-Object -Property $outputFields | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
            $outputContext.AccountCorrelated = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = 'CorrelateAccount'
                    Message = "Correlated to account [$($correlatedAccount.USERNAME)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                    IsError = $false
                })
            break
        }

        'MultipleFound' {
            throw "Multiple accounts found where [$correlationField] = [$correlationValue]. Please correct this so the accounts are unique."
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
