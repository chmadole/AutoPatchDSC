Configuration PatchOneServer {
    If (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration
    Import-DscResource -ModuleName @{ModuleName="AutoPatchDsc"; RequiredVersion="1.4.2"}

    Node 'Server01'{
        #Install patches during maintenance window
        AutoPatchInstall InstallOSPatches {
            Name             = 'InstallOSPatches'
            PatchWindowStart = 'January 1st, 2017 2am'
            PatchWindowEnd   = 'January 1st, 2017 4am'
        }

        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL' #Resource will start these services if needed, and returns true if they are running
            ServicesToAttemptStarting          = (Get-WmiObject Win32_Service | Where-Object { $_.StartMode -eq 'Auto'}).Name #Resource will start these services if needed, and returns true regardless if they are running or not
        }
    
        #Reboot server on completion of patch installation
        AutoPatchReboot LocalReboot {
            Name             = 'LocalReboot'
            PatchWindowStart = 'January 1st, 2017 2am'
            PatchWindowEnd   = 'January 1st, 2017 4am'
            RebootMode       = 'MaintenanceWindowAutomaticReboot'
        }
    }
}

Configuration PatchTwoServers {
    If (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration
    Import-DscResource -ModuleName @{ModuleName="AutoPatchDsc"; RequiredVersion="1.4.2"}

    Node 'SqlServer01'{ 
        AutoPatchInstall InstallOSPatches {
            Name                          = 'InstallOSPatches'
            PatchWindowStart              = 'January 1st, 2017 2am'
            PatchWindowEnd                = 'January 1st, 2017 3am'
            InstallPatchesDuringPreflight = $True #Allows patches to begin installing before the maintenance window starts in a 'preflight' window
            PreflightWindowStart          = 'January 1st, 2017 1am' #Sets the start time of the 'preflight' window
        }

        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL' #Resource will start these services if needed, and returns true if they are running
        }
    
        #Reboot server on completion of patch installation
        AutoPatchReboot LocalReboot {
            Name                 = 'LocalReboot'
            PreflightWindowStart = 'January 1st, 2017 1am' 
            PatchWindowStart     = 'January 1st, 2017 2am'
            PatchWindowEnd       = 'January 1st, 2017 3am'
            RebootMode           = 'PreFlightWindowAutomaticReboot' #Server will reboot between 1 - 2 am
        }
    }

    Node 'SqlServer02' {
        AutoPatchInstall InstallOSPatches {
            Name                          = 'InstallOSPatches'
            PatchWindowStart              = 'January 1st, 2017 3am'
            PatchWindowEnd                = 'January 1st, 2017 4am'
            InstallPatchesDuringPreflight = $True
            PreflightWindowStart          = 'January 1st, 2017 1am'
        }
    
        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL'
        }

        #Resource to wait for SqlServer01 to reboot
        WaitForAll SqlServer01LocalReboot {
            ResourceName     = '[AutoPatchReboot]LocalReboot'
            NodeName         = 'SqlServer01'
            RetryIntervalSec = 60
            RetryCount       = 5
        }

        AutoPatchReboot LocalReboot {
            Name             = 'LocalReboot'
            PatchWindowStart = 'January 1st, 2017 3am'
            PatchWindowEnd   = 'January 1st, 2017 4am'
            DependsOn        = '[WaitForAll]SqlServer01LocalReboot'
            RebootMode       = 'MaintenanceWindowAutomaticReboot'
        }
    }
} 