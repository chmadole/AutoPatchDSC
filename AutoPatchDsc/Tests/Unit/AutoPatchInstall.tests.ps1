$script:DSCModuleName   = 'AutoPatchDsc'
$script:DSCResourceName = 'AutoPatchInstall'

Import-module AutoPatchDsc

<#
#region HEADER
[String] $script:moduleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:MyInvocation.MyCommand.Path))
if ( (-not (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
     (-not (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $moduleRoot -ChildPath '\DSCResource.Tests\'))
}
else
{
    & git @('-C',(Join-Path -Path $moduleRoot -ChildPath '\DSCResource.Tests\'),'pull')
}
Import-Module (Join-Path -Path $moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1') -Force
$TestEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:DSCModuleName `
    -DSCResourceName $script:DSCResourceName `
    -TestType Unit 
#endregion
#>

# Begin Testing
try {
    #region Pester Tests

    #create sample parameter sets
    $script:propertySets = @(
        @{  Name             = 'InstallOSPatches'
            PatchWindowStart = Get-Date '1/1/2017 2am'
            PatchWindowEnd   = Get-Date '1/1/2017 4am' 
            }
        @{  Name                          = 'InstallOSPatches'
            PreflightWindowStart          = Get-Date '1/1/2017 1am'
            PatchWindowStart              = Get-Date '1/1/2017 2am'
            PatchWindowEnd                = Get-Date '1/1/2017 4am'
            InstallPatchesDuringPreflight = $True 
            }
    )

    #test each Property Set Individually
    $parameterSetNumber = 1
    Foreach ($script:properties in $script:propertySets) {
        Describe "$script:DSCResourceName.Get() - Testing Parameter Set #$parameterSetNumber" {
            It 'Should not throw an exception' {
                { $get = Invoke-DscResource -Name AutoPatchInstall -Method Get -Property $script:properties -ModuleName AutoPatchDSC } |
                Should Not Throw
            }
        }

        $parameterSetNumber++
    }
} finally {
    #region FOOTER
    #Restore-TestEnvironment -TestEnvironment $TestEnvironment
    #endregion
}