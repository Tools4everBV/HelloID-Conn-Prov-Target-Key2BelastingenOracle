$config = $configuration | ConvertFrom-Json;
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

$DataSource = $config.dataSource
$Username = $config.username
$Password = $config.password

$OracleConnectionString = "User Id=$Username;Password=$Password;Data Source=$DataSource"

# Change mapping here
$account = [PSCustomObject]@{
    USERNAME 					= $aRef;
    LOCK_STATUS 				= "LOCK";
};

if(-Not($dryRun -eq $True)) {
    try{
		$null =[Reflection.Assembly]::LoadWithPartialName("System.Data.OracleClient")

        $create = $true

		#check correlation before create
        $OracleConnection = New-Object System.Data.OracleClient.OracleConnection($OracleConnectionString)
        $OracleConnection.Open()
        Write-Verbose -Verbose "Successfully connected Oracle to database '$DataSource'" 
			
        $OracleCmd = $OracleConnection.CreateCommand()
     
        $OracleQueryCreate = "ALTER USER $($account.USERNAME) ACCOUNT $($account.LOCK_STATUS)"

        Write-Verbose -Verbose $OracleQueryCreate
        
        $OracleCmd.CommandText = $OracleQueryCreate
        $OracleCmd.ExecuteNonQuery() | Out-Null
        
        Write-Verbose -Verbose "Successfully performed Oracle creation query."

        $success = $True;
        $auditMessage = " succesfully";   
    
    } catch {
        Write-Error $_
    }finally{
        if($OracleConnection.State -eq "Open"){
            $OracleConnection.close()
        }
        Write-Verbose -Verbose "Successfully disconnected from Oracle database '$DataSource'"
    }
}

$success = $True;
$auditLogs.Add([PSCustomObject]@{
    # Action = "EnableAccount"; Optionally specify a different action for this audit log
    Message = "Account $($aRef) enabled";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AuditLogs = $auditLogs;
    Account = $account;
};
Write-Output $result | ConvertTo-Json -Depth 10;
