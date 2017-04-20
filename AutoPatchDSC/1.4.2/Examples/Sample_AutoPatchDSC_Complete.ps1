# Set the LCM to allow reboot of the node if needed, otherwise the server will not be able to reboot
[DscLocalConfigurationManager()]
Configuration LcmConfig {
    Node 'Server01' {
        Settings {
            RebootNodeIfNeeded = $true
        }
    }
}

# This example installs any patches avialable from WSUS between 2am - 4am.
# The server will reboot during the maintenance window between 2am - 4am.
Configuration PatchOneServer {
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration
    Import-DscResource -ModuleName @{ModuleName="AutoPatchDsc"; RequiredVersion="1.4.2"}

    # AutoPatchDSC has a dependency on PSWindowsUpdate -- you will need to download this from the PowerShell Gallery website.
    If (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}
    
    Node 'Server01'{
        #Install patches during maintenance window 2am - 4am
        AutoPatchInstall InstallOSPatches {
            Name             = 'InstallOSPatches'
            PatchWindowStart = 'January 1st, 2017 2am'
            PatchWindowEnd   = 'January 1st, 2017 4am'
        }

        # A start-service call wiill be executed for all services listed (if the service isn't running).
        # The resource tests false if an resources listed under 'ServicesrequiredToContinuePatching' are not running.
        # If a services listed under 'ServicestoAttemptStarting' is not running, it will not impact the return of the Test,
        # but an attempt will be made to start it.
        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL' #Resource will start these services if needed, and returns true if they are running
            ServicesToAttemptStarting          = (Get-WmiObject Win32_Service -ComputerName $Node.nodename | Where-Object { $_.StartMode -eq 'Auto'}).Name #Resource will start these services if needed, and returns true regardless if they are running or not
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

# This example illustrates patching two servers and rebooting them during different windows.
Configuration PatchTwoServers {
    Import-DscResource -ModuleName PSDesiredStateConfiguration, xWebAdministration
    Import-DscResource -ModuleName @{ModuleName="AutoPatchDsc"; RequiredVersion="1.4.2"}

    # AutoPatchDSC has a dependency on PSWindowsUpdate -- you will need to download this from the PowerShell Gallery website.
    If (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}

    Node 'SqlServer01'{ 
        #Install patches during the preflight window 1am - 2am or during the maintenance window 2am - 3am
        AutoPatchInstall InstallOSPatches {
            Name                          = 'InstallOSPatches'
            PreflightWindowStart          = 'January 1st, 2017 1am'
            PatchWindowStart              = 'January 1st, 2017 2am'
            PatchWindowEnd                = 'January 1st, 2017 3am'
            InstallPatchesDuringPreflight = $True 
        }

        # A start-service call wiill be executed for all services listed (if the service isn't running).
        # The resource tests false if an resources listed under 'ServicesrequiredToContinuePatching' are not running.
        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL'
        }
    
        #Reboot server on completion of patch installation during the preflight window only, 1am - 2am
        AutoPatchReboot LocalReboot {
            Name                 = 'LocalReboot'
            PreflightWindowStart = 'January 1st, 2017 1am' 
            PatchWindowStart     = 'January 1st, 2017 2am'
            PatchWindowEnd       = 'January 1st, 2017 3am'
            RebootMode           = 'PreFlightWindowAutomaticReboot'
        }
    }

    Node 'SqlServer02' {
        #Install patches during the preflight window 1am - 2am or during the maintenance window 3am - 4am
        AutoPatchInstall InstallOSPatches {
            Name                          = 'InstallOSPatches'
            PatchWindowStart              = 'January 1st, 2017 3am'
            PatchWindowEnd                = 'January 1st, 2017 4am'
            InstallPatchesDuringPreflight = $True
            PreflightWindowStart          = 'January 1st, 2017 1am'
        }
    
        # A start-service call wiill be executed for all services listed (if the service isn't running).
        # The resource tests false if an resources listed under 'ServicesrequiredToContinuePatching' are not running.
        AutoPatchServices LocalServices {
            Name                               = 'LocalServices'
            ServicesRequiredToContinuePatching = 'MsSQL'
        }

        #Resource to wait for SqlServer01 to reboot, retrying 5 times at one minute intervals
        WaitForAll SqlServer01LocalReboot {
            ResourceName     = '[AutoPatchReboot]LocalReboot'
            NodeName         = 'SqlServer01'
            RetryIntervalSec = 60
            RetryCount       = 5
        }

        # Reboot the server during the maintenance window 3am - 4am, only if the WaitForAll resource of
        # SqlServer01LocalReboot tests true at runtime.
        #
        # NOTE: a bug in the 5.0 version of the WaitForAll resource sometimes allows the WaitForAll resource
        # to return $true, then immediately execute on a reboot on the server being waited on.  It is unknown
        # if this bug has been resolved in the 5.1 version of PowerShell.  This effect happens
        # because the Set-TargetResource methods returns $true, but doesn't take into account whether the 
        # server was flagged for reboot.  If you can tolerate an occassional out of band reboot on your service,
        # this might not be a problem, because the conditions which allow for it occur infrequently.
        # However if you are adhering to strict SLA and cannot tolerate an out of band reboot, it's best to use
        # a controller script instead.  A simple way to do this is to toggle the RebootNodeIfNeeded on the LCM,
        # for example from 2-3am Server1 can reboot, from 3-4am Server2 can reboot.
        AutoPatchReboot LocalReboot {
            Name             = 'LocalReboot'
            PatchWindowStart = 'January 1st, 2017 3am'
            PatchWindowEnd   = 'January 1st, 2017 4am'
            DependsOn        = '[WaitForAll]SqlServer01LocalReboot'
            RebootMode       = 'MaintenanceWindowAutomaticReboot'
        }
    }
} 