#write log with verbose option
Function Write-AutoPatchLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string] $message,

        [string] $logFile = $Global:AutoPatchDSCLogFile,

        [switch] $writeError,
        [switch] $writeWarning,
        [switch] $writeInformation,
        [switch] $writeDebug
    )
    (Get-PSCallStack)[1].command

    #Default if non specified
    if ($logfile -eq '') {$logFile = 'C:\Windows\AutoPatchLog.txt'}
            
    #make sure log directory exists
    $logDir = (Split-path $logFile)
    if (-not (test-path -PathType Container -Path $logDir)) {New-Item -ItemType Directory -Path $logDir}

    #Write to the log file and verbose stream
    $output = "[$((Get-PSCallStack)[2].command):$((Get-PSCallStack)[1].command)] $(Get-Date): $message"

    try {
        $output | Out-File -FilePath $logFile -Append
    } catch {
        Write-Error $_.Exception
    }
    
    if     ($writeError)       {Write-Error       $output}
    elseif ($writeWarning)     {Write-Warning     $output}
    elseif ($writeDebug)       {Write-Debug       $output}
    elseif ($writeInformation) {Write-Information $output}
    else                       {Write-Verbose     $output}
}
 