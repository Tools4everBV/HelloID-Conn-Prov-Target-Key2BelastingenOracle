$config = $configuration | ConvertFrom-Json;
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$success = $False;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];

function Get-RandomCharacters($length, $characters) {
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs=""
    return [String]$characters[$random]
}

function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}

function GenerateRandomPassword(){
    $password = Get-RandomCharacters -length 4 -characters 'abcdefghiklmnoprstuvwxyz'
    $password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += Get-RandomCharacters -length 2 -characters '1234567890'
    #$password += Get-RandomCharacters -length 2 -characters '!§$%&/()=?}][{#*+'

    $password = Scramble-String $password

    return $password
}

$accountReference = ($p.Accounts.MicrosoftActiveDirectoryCorp.SamAccountName).ToUpper();

$DataSource = $config.dataSource
$Username = $config.username
$Password = $config.password

$OracleConnectionString = "User Id=$Username;Password=$Password;Data Source=$DataSource"

# Change mapping here
$account = [PSCustomObject]@{
    USERNAME 					= $accountReference;
    DEFAULT_TABLESPACE 			= "USERS";
    DEFAULT_TABLESPACE_QUOTA 	= "10M";
    TEMPORARY_TABLESPACE 		= "TEMP10";
    PROFILE 					= "GHS_PROFILE_PW_BEHEER";
    EXPIRE                      = $false;
	LOCK_STATUS 				= "UNLOCK";
    PASSWORD                    = GenerateRandomPassword
};

if(-Not($dryRun -eq $True)) {
    try{
		$null =[Reflection.Assembly]::LoadWithPartialName("System.Data.OracleClient")
		
        $OracleConnection = New-Object System.Data.OracleClient.OracleConnection($OracleConnectionString)
        $OracleConnection.Open()
        Write-Verbose -Verbose "Successfully connected Oracle to database '$DataSource'" 
        
        #Geen correlatie, er moet altijd een unieke Username worden aangemaakt
        $unique = $false
        $i=0
        $maxIterations = 10
        while(-not($unique) -and $i -lt $maxIterations)
        {
            if($i -gt 0)
            {
                $account.USERNAME = $account.USERNAME + "$i"
            }
            
            $OracleQuery = "SELECT USERNAME FROM SYS.DBA_USERS WHERE USERNAME = '$($account.USERNAME)'"
            $OracleCmd = $OracleConnection.CreateCommand()
            $OracleCmd.CommandText = $OracleQuery

            $OracleAdapter = New-Object System.Data.OracleClient.OracleDataAdapter($cmd)
            $OracleAdapter.SelectCommand = $OracleCmd;

            # Execute the command against the database, returning results.
            $DataSet = New-Object system.Data.DataSet
            $null = $OracleAdapter.fill($DataSet)

            $result = $DataSet.Tables[0] | Select-Object -Property * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors;

            Write-Verbose -Verbose "Successfully performed Oracle '$OracleQuery'. Returned [$($DataSet.Tables[0].Columns.Count)] columns and [$($DataSet.Tables[0].Rows.Count)] rows"
            
            $rowcount = $($DataSet.Tables[0].Rows.Count)
            
            if($rowcount -eq 0){    
                $unique = $true
            }
            $i++
        }

        if(-not($unique)){
            Write-Error "Used $maxIterations iterations and no unique USERNAME was found"
            $success = $False
        }
        else {
            #Write-Verbose -Verbose "No existing user found. Creating new user"
            
            $OracleQueryCreate = "		
                CREATE USER $($account.USERNAME)
                IDENTIFIED  BY `"$($account.PASSWORD)`"
                DEFAULT TABLESPACE $($account.DEFAULT_TABLESPACE)
                QUOTA $($account.DEFAULT_TABLESPACE_QUOTA) ON $($account.DEFAULT_TABLESPACE)
                TEMPORARY TABLESPACE $($account.TEMPORARY_TABLESPACE)
                PROFILE $($account.PROFILE)
                ACCOUNT $($account.LOCK_STATUS)"
        
            Write-Verbose -Verbose $OracleQueryCreate
            
            $OracleCmd.CommandText = $OracleQueryCreate
            $OracleCmd.ExecuteNonQuery() | Out-Null
			
            Write-Verbose -Verbose "Successfully performed Oracle creation query."

            $success = $True;
            $auditMessage = " succesfully";   
		}
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
    # Action = "CreateAccount"; Optionally specify a different action for this audit log
    Message = "Created account with username $($account.userName)";
    IsError = $False;
});

# Send results
$result = [PSCustomObject]@{
	Success= $success;
	AccountReference= $accountReference;
	AuditLogs = $auditLogs;
    Account = $account;

    # Optionally return data for use in other systems
    ExportData = [PSCustomObject]@{
        USERNAME = $account.USERNAME;
    };
    
};
Write-Output $result | ConvertTo-Json -Depth 10;
