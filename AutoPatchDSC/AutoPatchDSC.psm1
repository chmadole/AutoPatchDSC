Get-ChildItem (Join-Path $PSScriptRoot *.ps1) | % { . $_.FullName}

#region AutoPatchInstall Class
    <#
        --------------------------------------------------------------------------------
        This resource provides automated patching during a defined patch window.
        It is designed for use with WaitFor* constructs to allow reboots of different
        servers in a farm to reboot at different times to maintain high availability of
        a particular service such as SQL or SharePoint.  However, the module should
        work with farms of any type.
    #>

    [DscResource()]
    class AutoPatchInstall {

    #region AutoPatchInstall PROPERTIES 
        <#  Provides a unique name for the instance of the resource. #>
            [DscProperty(Key)]
            [string] $Name
          
        <#  Provides a starting date and time for the maintenance window.  Patching and
            reboot can always occur after this time until the $PatchWindowEnd date and time. #>
            [DscProperty()]
            [Nullable[datetime]] $PatchWindowStart

        <#  Provides a ending date and time for the maintenance window.  Patching and reboot
            can always occur before this time and after the $PatchWindowStart date and time. #>
            [DscProperty()]
            [Nullable[datetime]] $PatchWindowEnd

        <#  Provides a preparation window before the PatchWindowStart when patches can be
            installed, but reboots will not occur until the maintenance window, unless
            $RebootDuringPreFlight is set to $True, then they can also occur during the
            preflight window.  Parameter accepts a datetime object. #>
            [DscProperty()]
            [Nullable[datetime]] $PreflightWindowStart

        <#  Path to file for logging.  Must be local.#>
            [DscProperty()]
            [String]$LogFile

        <#  Gives the option to install patches during preflight instead of just downloading them. #>
            [DscProperty()]
            [bool]$InstallPatchesDuringPreflight = $True

        <#  Read-only property to report the status of the WSUS installer (idle/busy/offline) #>
            [DscProperty(NotConfigurable)]
            [string]$WsusInstallerStatus

        <#  Read-only property to report the which KBs by number are pending installation. #>
            [DscProperty(NotConfigurable)]
            [string]$UpdatesPendingInstall
    
        <#  Read-only property to report whether updates installed by WSUS are pending a reboot. #>
            [DscProperty(NotConfigurable)]
            [bool]$PendingRebootRequired

        <#  Read-only property that servers as a point in time when DSC configuration ran. #>
            [DscProperty(NotConfigurable)]
            [datetime]$RunTime = $(Get-Date)

        <# Read-only property for whether the server is in or out of the preflight window at runtime. #>
            [DscProperty(NotConfigurable)]
            [bool]$inPreFlightWindow

        <#  Read-only property for whether the server is in or out of the maintenance window at runtime. #>
            [DscProperty(NotConfigurable)]
            [bool]$inMaintenanceWindow

        <#  Read-only identifying last bootuptime of the server. #>
            [DscProperty(NotConfigurable)]
            [String]$LastBootUpTime

        <#  Non-DscProperty - tracks whether the wsus installer is busy or not. #>
            [bool]$WsusInstallerBusy

        <#  Non-DscProperty - contains object returned by get-wulist with information about needed patches #>
            [Object]$wuList

        <#  Non-DscProperty - tracks whether the wsus installer is busy or not. #>
            [int]$patchInstallPassNumber
    #endregion AutoPatchInstall PARAMETERS

    #region AutoPatchInstall Set
        <#  When a server is found out of compliance (e.g. in a maintenance window + needing patches) this Set
            method will cause the server to download patches, patch the server and reboot. #>
        [void] Set()
        {
            $this.initialize()

            #Just in case, if there are no updates, no pending reboot and the installer isn't busy, don't do anything!
            If ( ($this.wulist -eq $null) -and !$this.pendingRebootRequired -and !$this.WsusInstallerBusy)
            {
                Write-AutoPatchLog '[AutoPatchInstall:Set] Server does not need patches.'
            }
            #If there ARE updates, and there are no reboots pending, install patches
            ElseIf (($this.wulist -ne $Null) -and !$this.pendingRebootRequired)
            {
                Write-AutoPatchLog '[AutoPatchInstall:Set] Server needs patches.'
            
                If     ($this.inPreFlightWindow -and $this.InstallPatchesDuringPreflight)  {$this.installPatches()}
                elseif ($this.inPreFlightWindow -and !$this.InstallPatchesDuringPreflight) {$this.downloadPatches()}
                elseif ($this.inMaintenanceWindow)                                         {$this.installPatches()}
                else   {Write-AutoPatchLog '[AutoPatchInstall:Set] Cannot install patches until preflight or maintenance window.'}
            } 
            ElseIf ($this.WsusInstallerBusy)
            {
                Write-AutoPatchLog '[AutoPatchInstall:Set] Server is busy installing updates.'
            }
            ElseIf ($this.pendingRebootRequired)
            {
                Write-AutoPatchLog '[AutoPatchInstall:Set] Server is pending a reboot.'
            }
        } 
    #endregion AutoPatchInstall SET

    #region AutoPatchInstall TEST
        <# This method tests the compliance of the automated patching configuration and reports $True or $False #>
        [bool] Test()
        {
            $this.initialize()

            If ( ($this.wulist -eq $null) -and !$this.pendingRebootRequired -and !$this.WsusInstallerBusy)
            {   #no updates to install and no reboot pending 
                Write-AutoPatchLog '[AutoPatchInstall:Test] Server does not need patches.'
                Return $True
            }            
            ElseIf (($this.wulist -ne $Null) -and !$this.pendingRebootRequired) {
                Write-AutoPatchLog "[AutoPatchInstall:Test] Server needs patches: $($this.updatesPendingInstall)"
                Return $false
            }
            ElseIf ($this.WsusInstallerBusy) {
                Write-AutoPatchLog '[AutoPatchInstall:Test] Server is installing updates.'
                Return $false
            }
            ElseIf ($this.pendingRebootRequired) {
                Write-AutoPatchLog '[AutoPatchInstall:Test] Server is pending reboots.'
                Return $false
            }
            Else {
                Write-AutoPatchLog '[AutoPatchInstall:Test] The AutoPatch DSC Script resource could not determine the patch state of the server.'
                Return $False
            }
        }
     #endregion AutoPatchInstall Test

    #region AutoPatchInstall GET
        <# This method gets the status of patch need and defined maintenance windows. #>
        [AutoPatchInstall] Get()
        {
            $this.initialize()
            Return $this
        }
    #endregion AutoPatchInstall GET

    #region AutoPatchInstall HELPER FUNCTIONS
        <# Function to initialize AutoPatch evaluating window status and what updates are pending installation. #>
        [void] initialize(){
            if (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}

            $this.LastBootUpTime        = $(Get-CimInstance -ClassName win32_OperatingSystem).lastbootuptime  #Note: this is producing extra output; could be improved by supressing it becuase it's not helpful.  Try: -Verbose 4>&1 | Out-Null
            $this.inPreFlightWindow     = ($this.RunTime -ge $this.preflightStart)   -and ($this.RunTime -lt $this.patchWindowStart)
            $this.inMaintenanceWindow   = ($this.RunTime -ge $this.patchWindowStart) -and ($this.RunTime -lt $this.patchWindowEnd)
            $this.wuList                = Get-WUList -NotCategory 'Definition Updates' # this produces extra output, but it's helpful, so I'm leaving it for now.
            $this.UpdatesPendingInstall = [String]$(($this.wuList).kb)
            $this.PendingRebootRequired = $(Get-WURebootStatus -Silent)
            $this.WsusInstallerStatus   = Get-WUInstallerStatus
            $this.WsusInstallerBusy     = (Get-WUInstallerStatus -Silent)

            if ($this.inPreFlightWindow -or $this.inMaintenanceWindow) {
                Write-AutoPatchLog "Runtime: $($this.RunTime)"
                Write-AutoPatchLog "Last BootUp Time: $($this.LastBootUpTime)"
                Write-AutoPatchLog "In PreFlight Window: $($this.inPreFlightWindow)"
                Write-AutoPatchLog "In Maintenance Window: $($this.inMaintenanceWindow)"
                Write-AutoPatchLog "Updates Pending Installation: $($this.UpdatesPendingInstall)"
                Write-AutoPatchLog "Pending Reboot Required: $($this.PendingRebootRequired)"
                Write-AutoPatchLog "WSUS Installer Status: $($this.WsusInstallerStatus)"
            }
        }


        #Helper Function to install patches
        [void]installPatches() {
            $this.patchInstallPassNumber++
                
            Write-AutoPatchLog "Installing Patches: `n$($this.updatesPendingInstall)"
                
            $output = Get-WUInstall -IgnoreReboot -AcceptAll

            if (!$?) {
                Write-AutoPatchLog $output #error was with 59 WC01 Prod... check the event log for wsus errors.
            }
                
            # Recursive call to expedite further patching or a reboot if needed;
            # Otherwise, the subsequent patching or reboot won't go until the next DSC cycle.
            # The recursion should always terminate, however the patchInstallPassNumber check
            # is a simple precaution to prevent runaway recursion.
            if ($this.patchInstallPassNumber -lt 3) { $this.set() }
            #>
        }

        #Helper Function to download patches
        [void]downloadPatches() {
            Write-AutoPatchLog "Downloading Patches: `n$($this.updatesPendingInstall)"
            $output = Get-WUInstall -DownloadOnly -AcceptAll
            if (!$?) {
                Write-AutoPatchLog $output
            }
        }
    #endregion AutoPatchInstall HELPER FUNCTIONS
    }
#endregion AutoPatchInstall

#region AutoPatchServices Class
    <#
        This resource makes sure that all specified services are running so that for
        automated patching with other AutoPatchDSC resources occurs successfully.
    #>

    [DscResource()]
    class AutoPatchServices {
        <#  Provides a unique name for the instance of the resource. #>
            [DscProperty(Key)]
            [string] $Name

        <#  Provides a list of services which should be running in order for AutoPatch to proceed #>
            [DscProperty()]
            [string[]] $ServicesRequiredToContinuePatching

            [DscProperty()]
            [string[]] $ServicesToAttemptStarting = (Get-WmiObject Win32_Service | Where-Object { $_.StartMode -eq 'Auto'}).Name

            [DscProperty(NotConfigurable)]
            [String[]]$currentServiceState

        #region AutoPatchServices Set
            <# This method will attempt to start all services defined in the $ServicesRequiredToContinuePatching array #>
            [void] Set()
            {
                if ($this.ServicesRequiredToContinuePatching) {
                    Write-AutoPatchLog "[AutoPatchServices] Attempting to start required services ($this.ServicesRequiredToContinuePatching)"
                
                    Foreach ($service in $this.ServicesRequiredToContinuePatching) {
                        try {
                            (Get-Service -Name $service -ErrorAction Stop | ? Status -ne 'Running').Name | Start-Service -ErrorAction Stop
                        } catch {
                            Write-AutoPatchLog "[AutoPatchServices] Failed to start required service $service."
                        }
                    }
                }
            }
        #endregion AutoPatchServices Set

        #region AutoPatchServices Test
            <# This method will check if all services defined in the $services array are started#>
            [bool] Test()
            {
                <#
                $servicesString = $null
                (Get-Service -Name $this.ServicesRequiredToContinuePatching | ? Status -eq 'Running').Name | % {$servicesString += "$_, "}
                $currentRunningServices  = $servicesString.Trim(', ')
                #>
                $currentRunningServices  = (Get-Service | ? Status -eq 'Running').Name
                $optionalServicesToStart = (Compare-Object $This.ServicesToAttemptStarting $currentRunningServices | ? SideIndicator -eq '<=').inputobject

                if ($optionalServicesToStart) {
                    Write-AutoPatchLog "[AutoPatchServices] Attempting to start optional services $optionalServicesToStart"
                    
                    Foreach ($service in $optionalServicesToStart) {
                        try {
                            (Get-Service -Name $service -ErrorAction Stop | ? Status -ne 'Running').Name | Start-Service -ErrorAction Stop
                        } catch {
                            Write-AutoPatchLog "[AutoPatchServices] Failed to start optional service $service."
                        }
                    }
                }

                if ($this.ServicesRequiredToContinuePatching) {
                    $requiredServicestoStart = (Compare-Object $This.ServicesRequiredToContinuePatching $currentRunningServices | ? SideIndicator -eq '<=').Name

                    if ($requiredServicestoStart) {
                        Write-AutoPatchLog "[AutoPatchServices] The following required services are not running $requiredServicestoStart."
                        Return $false
                    } else {
                        Return $true
                    }
                } else {
                    Return $true
                }
            } 
        #endregion AutoPatchServices Test

        #region AutoPatchServices Get
            <# This method will return information about whether the services are started#>
            [AutoPatchServices] Get()
            {
                $this.currentServiceState = Get-Service -Name $this.ServicesRequiredToContinuePatching | sort -Property Status
                Return $this
            }
        #endregion AutoPatchServices Get
    }
#endregion AutoPatchServices Class

#region AutoPatchReboot Class
    <#
        --------------------------------------------------------------------------------
        This resource provides automated rebooting of machines that have been patched
        during a defined patch window.  It's designed for concerted use with the 
        AutoPatchInstall DSC resource and with WaitFor* constructs to allow reboots
        servers in a farm to reboot at different times to maintain high availability of
        a particular service such as SQL, SharePoint, etc.
    #>

    [DscResource()]
    class AutoPatchReboot {

    #region AutoPatchReboot PROPERTIES 
        <#  Provides a unique name for the instance of the resource. #>
            [DscProperty(Key)]
            [string] $Name
          
        <#  Provides a starting date and time for the maintenance window.  Patching and
            reboot can always occur after this time until the $PatchWindowEnd date and time. #>
            [DscProperty()]
            [Nullable[datetime]] $PatchWindowStart

        <#  Provides a ending date and time for the maintenance window.  Patching and reboot
            can always occur before this time and after the $PatchWindowStart date and time. #>
            [DscProperty()]
            [Nullable[datetime]] $PatchWindowEnd

        <#  Provides a preparation window before the PatchWindowStart when patches can be
            installed, but reboots will not occur until the maintenance window, unless
            $RebootDuringPreFlight is set to $True, then they can also occur during the
            preflight window.  Parameter accepts a datetime object. #>
            [DscProperty()]
            [Nullable[datetime]] $PreflightWindowStart

        <#  When AutoPatchReboot runs on a hypervisor, by default the hosted VMs will follow
            their Automatic Stop and Automatic Start settings in Hyper-V Manager.  This
            setting allows you to force suspend the VMs.  This will prevent shutdown
            #>
            [DscProperty()]
            [ValidateSet('Save','Shutdown','')]
            [String] $HyperVisorVMPreference

        <#  By default, AutoPatch will only cause servers to reboot during the maintenance
            window.  Set RebootDuringPreFlight = $True if you want the AutoPatch to also reboot
            servers during the preflight window.  This might be useful for servers like an SQL
            witness server. #>
            [DscProperty(Mandatory)]
            [ValidateSet('PreFlightWindowAutomaticReboot','MaintenanceWindowAutomaticReboot','AnyWindowAutomaticReboot','ManualReboot')]
            [String] $RebootMode

        <#  The maximum number of reboots the server can have as executed by AutoPatchReboot
            in a given patch window.  #>
            [DscProperty()]
            [int]$maxReboots = 3

        <#  Read-only identifying last bootuptime of the server. #>
            [DscProperty()]
            [String]$LogFile

        <#  Read-only property to report the which KBs by number are pending installation. #>
            [DscProperty(NotConfigurable)]
            [string]$UpdatesPendingInstall

        <#  Read-only property to report the status of the WSUS installer (idle/busy/offline) #>
            [DscProperty(NotConfigurable)]
            [string]$WsusInstallerStatus

        <#  Non-DscProperty - tracks whether the wsus installer is busy or not. #>
            [bool]$WsusInstallerBusy

        <#  Read-only property to report whether updates installed by WSUS are pending a reboot. #>
            [DscProperty(NotConfigurable)]
            [bool]$PendingRebootRequired

        <#  Read-only property that servers as a point in time when DSC configuration ran. #>
            [DscProperty(NotConfigurable)]
            [datetime]$RunTime = $(Get-Date)

        <# Read-only property for whether the server is in or out of the preflight window at runtime. #>
            [DscProperty(NotConfigurable)]
            [bool]$inPreFlightWindow

        <#  Read-only property for whether the server is in or out of the maintenance window at runtime. #>
            [DscProperty(NotConfigurable)]
            [bool]$inMaintenanceWindow

        <#  Read-only identifying last bootuptime of the server. #>
            [DscProperty(NotConfigurable)]
            [String]$LastBootUpTime
                
        <#  Non-DscProperty - contains object returned by get-wulist with information about needed patches #>
            [Object]$wuList

    #endregion AutoPatchReboot PROPERTIES 

    #region AutoPatchReboot SET
        <#  When a server is found out of compliance (e.g. in a maintenance window + needs reboot) this Set
            method will cause the server to reboot.
        #>
        [void] Set()
        {
            $this.initialize()

            if     ($this.inPreflightWindow   -and $this.RebootMode -eq 'AnyWindowAutomaticReboot')         {$this.executeReboot()}
            elseif ($this.inPreflightWindow   -and $this.RebootMode -eq 'PreFlightWindowAutomaticReboot')   {$this.executeReboot()}
            elseif ($this.inPreflightWindow   -and $this.RebootMode -eq 'MaintenanceWindowAutomaticReboot') {Write-AutoPatchLog 'Cannot execute a reboot until the maintenance windows is reached.'}
            elseif ($this.inMaintenanceWindow -and $this.RebootMode -eq 'AnyWindowAutomaticReboot')         {$this.executeReboot()}
            elseif ($this.inMaintenanceWindow -and $this.RebootMode -eq 'PreFlightWindowAutomaticReboot')   {Write-AutoPatchLog 'Computer is set to reboot during preflight window, but the window has expired.'}
            elseif ($this.inMaintenanceWindow -and $this.RebootMode -eq 'MaintenanceWindowAutomaticReboot') {$this.executeReboot()}
            elseif ($this.RebootMode -eq 'ManualReboot')                                                    {Write-AutoPatchLog 'Computer is set to be manually rebooted.'}
            else   {Write-AutoPatchLog '[AutoPatchReboot:Set] Reboot action cannot be performed outside Preflight and Maintenance windows.' -writeWarning}
        } 
    #endregion AutoPatchReboot SET

    #region AutoPatchReboot TEST
        <# This method tests the compliance of the automated patching configuration and reports $True or $False #>
        [bool] Test()
        {
            $this.initialize()

            If ( $this.PendingRebootRequired        -and `
                ($this.WsusInstallerBusy -ne $true) -and `
                ($this.RebootMode -ne 'ManualReboot'))
            {
               #The test failed; the node needs a reboot and is in a state safe for reboot
               Return $False
            } else {
                Return $true
            }
        }
    #endregion AutoPatchReboot TEST

    #region AutoPatchReboot GET
        <# This method gets the status of patch need and defined maintenance windows. #>
        # Developer's Note: This output could be better by return a custom formatted hash table: $Configuration = [hashtable]::new()
        [AutoPatchReboot] Get()
        {
            $this.initialize()
            Return $this
        }
    #endregion AutoPatchReboot GET

    #region AutoPatchReboot HELPER FUNCTIONS
        <# Function to initialize AutoPatch evaluating window status and what updates are pending installation. #>
        [void] initialize(){
            if (-not (Get-Module PSWindowsUpdate)) {Import-Module PSWindowsUpdate}

            if ($this.LogFile) {$Global:AutoPatchDSCLogFile = $this.LogFile}

            $this.LastBootUpTime        = $(Get-CimInstance -ClassName win32_OperatingSystem).lastbootuptime  #Note: this is producing extra output; could be improved by supressing it becuase it's not helpful.  Try: -Verbose 4>&1 | Out-Null
            $this.inPreFlightWindow     = ($this.RunTime -ge $this.preflightStart)   -and ($this.RunTime -lt $this.patchWindowStart)
            $this.inMaintenanceWindow   = ($this.RunTime -ge $this.patchWindowStart) -and ($this.RunTime -lt $this.patchWindowEnd)
            $this.PendingRebootRequired = $(Get-WURebootStatus -Silent)
            $this.WsusInstallerStatus   = Get-WUInstallerStatus
            $this.WsusInstallerBusy     = (Get-WUInstallerStatus -Silent)
            $this.wuList                = Get-WUList -NotCategory 'Definition Updates' # this produces extra output, but it's helpful, so I'm leaving it for now.
            $this.UpdatesPendingInstall = [String]$(($this.wuList).kb)

            if ($this.inPreFlightWindow -or $this.inMaintenanceWindow) {
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] Last BootUp Time: $($this.LastBootUpTime)"
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] In PreFlight Window: $($this.inPreFlightWindow)"
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] In Maintenance Window: $($this.inMaintenanceWindow)"
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] Updates Pending Installation: $($this.UpdatesPendingInstall)"
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] WSUS Installer Status: $($this.WsusInstallerStatus)"
                Write-AutoPatchLog "[AutoPatchReboot:Initialize] Pending Reboot Required: $($this.PendingRebootRequired)"
            }
        }

        [void] executeReboot() {
            $window = ''
            if ($this.inMaintenanceWindow) {$window = 'MaintenanceWindow'} elseif ($this.inPreFlightWindow) {$window = 'PreflightWindow'}
            Write-AutoPatchLog "Reboot executed during $window with RebootMode of $($this.RebootMode)"

            #If the computer is a hypervisor, we must first handle the VMs
            if ((Get-WindowsFeature Hyper-V).'InstallState' -eq 'Installed') {
                if (-not (get-module hyper-v)) {Import-Module Hyper-V -ErrorAction Continue}
    
                switch ($this.HyperVisorVMPreference) {
                    'Save' {
                        Write-AutoPatchLog 'Saving VMs on Hyper-V Host'
                        Get-VM | Save-VM

                        $checkVMS = (get-vm).where{$_.state -eq 'running'}
                        if ($checkVMs) {
                            Write-AutoPatchLog "Some VMs on the host did not save correctly.  $($checkVMs.Name)" -writeError
                        } else {
                            Write-AutoPatchLog "All VMs were successfully saved."
                        }
                    }
                    'Shutdown' {
                        Write-AutoPatchLog 'Shutting down VMs on Hyper-V Host.'
                            
                        $jobs = Get-VM | Stop-VM -Force -AsJob
                        $jobs | Wait-Job

                        $checkVMS = (get-vm).where{$_.state -eq 'running'}
                        if ($checkVMs) {
                            Write-AutoPatchLog "Some VMs on the host did not shutdown correctly.  $($checkVMs.Name)" -writeError
                        } else {
                            Write-AutoPatchLog "SUCCESS: All VMs were successfully shutdown."
                        }
                    }
                    default {
                        Write-AutoPatchLog "No HyperVisorVMPreference action was specified so if any VMs are present they will follow the Automatic Stop and Automatic Start settings specified in Hyper-V.  If you do not wish to use these settings, set HyperVisorVMPreference='Suspend' in the AutoPatchReboot configuration and create xVMHyperV resources to ensure the desired VMs are running." -writeWarning
                    }
                } #end Switch
            } #end if
            
            [array]$rebootEvents = (Get-WinEvent -FilterHashtable @{logname='System'; id=1074; StartTime=$this.PreflightWindowStart} -ErrorAction SilentlyContinue).Where{$_.message -match 'DSC is restarting the computer'}

            if ($rebootEvents.Count -lt $this.maxReboots) {
                Write-AutoPatchLog '[AutoPatchReboot:executeReboot] EXECUTING REBOOT - Setting DSC Machine Status Reboot to 1.  DSC will shortly reboot this computer.' -writeWarning
                $global:DSCMachineStatus = 1
            } else {
                Write-AutoPatchLog "[AutoPatchReboot:executeReboot] FAILURE: AUTOPATCHDSC WILL NOT EXECUTE REBOOT - AutoPatchDSC has already rebooted this server $($rebootEvents.Count) times since the start of the preflight Window.  The maximum number of reboots is $($this.maxReboots).  The server will not be rebooted now to prevent reboot loops.  This indicates a patch may be failing to install properly -- please troubleshoot this server manually." -writeError
            }

        } #end executeReboot()

    #endregion AutoPatchReboot HELPER FUNCTIONS
    }
#endregion AutoPatchReboot Class
