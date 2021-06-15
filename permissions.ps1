$config = $configuration | ConvertFrom-Json;

$DataSource = $config.dataSource
$Username = $config.username
$Password = $config.password

$OracleConnectionString = "User Id=$Username;Password=$Password;Data Source=$DataSource"

try{
    $null =[Reflection.Assembly]::LoadWithPartialName("System.Data.OracleClient")

    $OracleConnection = New-Object System.Data.OracleClient.OracleConnection($OracleConnectionString)
    $OracleConnection.Open()
    Write-Verbose -Verbose "Successfully connected Oracle to database '$DataSource'" 
                    
    # Execute the command against the database
    $OracleQuery = "SELECT ROLE FROM SYS.DBA_ROLES"
    Write-Verbose -Verbose $OracleQuery
    $OracleCmd = $OracleConnection.CreateCommand()
    $OracleCmd.CommandText = $OracleQuery

    $OracleAdapter = New-Object System.Data.OracleClient.OracleDataAdapter($cmd)
    $OracleAdapter.SelectCommand = $OracleCmd;

    # Execute the command against the database, returning results.
    $DataSet = New-Object system.Data.DataSet
    $null = $OracleAdapter.fill($DataSet)

    $roles = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors;

    foreach($role in $roles)
    {
        $row = @{
            DisplayName = $role.ROLE;
            Identification = @{
                Id = $role.ROLE;
                DisplayName = $role.ROLE;
                Type = "Role";
            }
        };
        Write-Output ($row | ConvertTo-Json -Depth 10)
    }

} catch {
    Write-Error $_
}finally{
    if($OracleConnection.State -eq "Open"){
        $OracleConnection.close()
    }
    Write-Verbose -Verbose "Successfully disconnected from Oracle database '$DataSource'"
}