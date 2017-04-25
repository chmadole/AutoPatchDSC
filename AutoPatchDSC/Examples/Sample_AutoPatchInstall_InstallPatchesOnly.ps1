# This example installs any patches avialable from WSUS between 2am and 4am.
# It does not execute any reboots, nor install patches during the preflight window.
Configuration OnlyPatchServerNoReboot {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName @{ModuleName="AutoPatchDsc"; RequiredVersion="1.4.2"}

    # AutoPatchDSC has a dependency on PSWindowsUpdate -- you will need to download this from the PowerShell Gallery website.
    If (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}

    Node 'Server01'{
        #Install patches during maintenance window
        AutoPatchInstall InstallOSPatches {
            Name                          = 'InstallOSPatches'
            PreflightWindowStart          = 'January 1st, 2017 1am'
            PatchWindowStart              = 'January 1st, 2017 2am'
            PatchWindowEnd                = 'January 1st, 2017 4am'
            InstallPatchesDuringPreflight = $false
            LogFile                       = 'c:\locallogs\AutoPatchInstall.log'
        }
    }
}