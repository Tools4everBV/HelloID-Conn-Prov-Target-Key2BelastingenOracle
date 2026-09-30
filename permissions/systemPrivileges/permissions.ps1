#################################################
# HelloID-Conn-Prov-Target-Key2BelastingenOracle-Permissions-SystemPrivileges
# PowerShell V2
#################################################

# Managed system privileges. The HelloID service account must hold each privilege WITH ADMIN OPTION.
# Keep this list in sync with importPermissions.ps1.
$systemPrivileges = @(
    'CREATE SESSION'
)

try {
    Write-Information 'Starting import of Oracle system privilege permissions'

    $importedPermissions = 0
    foreach ($systemPrivilege in $systemPrivileges) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = "$systemPrivilege"
                Identification = @{
                    Id = "$systemPrivilege"
                }
            }
        )
        $importedPermissions++
    }

    Write-Information "Completed import of Oracle system privilege permissions. Result count: $($importedPermissions)"
}
catch {
    $ex = $PSItem
    $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    $errorMessage = "Error importing Oracle system privilege permissions. Error: $($ex.Exception.Message)"
    Write-Warning $warningMessage
    Write-Error $errorMessage
}
