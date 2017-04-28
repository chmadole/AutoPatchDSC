$script:DSCModuleName = 'AutoPatchDsc'

#region Pester Tests
Describe "$script:DSCModuleName Unit Tests" {
    Context 'Module Validation' {
        It "$script:DSCModuleName is valid PowerShell code" {
            $psFile = Get-Content -Path "$PSScriptRoot\..\..\$script:DSCModuleName.psm1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize($psFile, [ref]$errors)
            $errors.Count | Should Be 0
        }
    }
}
#endregion
