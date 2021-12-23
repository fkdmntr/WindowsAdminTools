#requires -version 3
<#
.SYNOPSIS
  Backup a Server using Windows Server Backup, with optional basic retention and archiving settings
.DESCRIPTION
  Backup either Bare Metal state of server (default mode) or selected volumes to a network backup destination. 
  Addtional options for deleting or archiving backups outside of a set period are available.
.PARAMETER BackupDestination    
    Backup destination root folder. Subfolders by machine name and date will be created here.
.PARAMETER LogPath 
    Logfile path - Defaults to Backup Destination if not specified
.PARAMETER Volumes 
    Specify mapped letter of volume(s) to backup. Comma seperated, colon optional. Overrides default bare-metal backup mode
.PARAMETER DeleteOld
    Optionally delete backups older than of BackupRetentionDays. Redundant if ArchiveOld is set.
.PARAMETER ArchiveOld
    Optionally move backups older than BackupRetentionDays to some folder
.PARAMETER BackupRetentionDays 
    Length of time in days (1-7300) to keep backups on the backup host. Mandatory if ArchiveOld or DeleteOld set
.PARAMETER ArchiveDestination 
    Destination for storing archived backups. Mandatory if ArchiveOld set. Machine-named subfolders created here, as with BackupDestination
.PARAMETER ArchiveRetentionDays 
    Length of time in days (1-7300) to keep backups on the archive host. Defaults to twice the BackupRetentionDays if not specified
.INPUTS
  None
.OUTPUTS Log File
  Log file stored in Backup Destination, unless otherwise specified
.NOTES
  Version:        1.0.6
  Author:         Aaron Clay
  Creation Date:  26Nov2018
  Purpose/Change: Moved Windows Server Backup param initialization to dedicated function.

.EXAMPLE
    Backup whole machine state to \\ExampleServer\BackupFolder. Dated logfiles to same.
  
    ServerBackup.ps1 -BackupDestination \\ExampleServer\BackupFolder

.EXAMPLE
    Backup D: and E: to \\ExampleServer\BackupFolder, logging to \\ExampleServer\LogFolder

    ServerBackup.ps1 -BackupDestination \\ExampleServer\BackupFolder -LogPath \\ExampleServer\LogPath -Volumes d,e

.EXAMPLE
    Backup D:, E: to \\ExampleServer\BackupFolder, log to *\LogFolder, Delete backups in destination older than 7 days

    ServerBackup.ps1 -BackupDestination \\ExampleServer\BackupFolder 
        -LogPath \\ExampleServer\LogPath 
        -Volumes d,e 
        -DeleteOld 
        -BackupRetentionDays 7

.EXAMPLE
    Backup Machine State to \\ExampleServer\BackupFolder, log to *\LogFolder, Move backups in destination older than 7 days to \\ArchiveServer\Archives. 
    Archived backups older than 14 days (BackupRetentionDays x2) will be deleted from the Archive. 

    ServerBackup.ps1 -BackupDestination \\ExampleServer\BackupFolder 
        -LogPath \\ExampleServer\LogPath 
        -ArchiveOld 
        -BackupRetentionDays 7
        -ArchiveDestination \\ArchiveServer\Archives

#>

[CmdletBinding(DefaultParameterSetName = "Default")]

Param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [Parameter(ParameterSetName = "Default")]
    [String]$BackupDestination,
        
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [String]$LogPath = $BackupDestination,

    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Volume", Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [array]$Volumes,
    
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Archive", Mandatory = $true)]
    [switch]$ArchiveOld = $false,
       
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Archive", Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchiveDestination,
        
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Archive", Mandatory = $false)]
    [ValidateRange(1, 7300)]
    [int]$ArchiveRetentionDays = 0,
        
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Delete", Mandatory = $true)]
    [switch]$DeleteOld = $false,
        
    [Parameter(ParameterSetName = "Default", Mandatory = $false)]
    [Parameter(ParameterSetName = "Archive", Mandatory = $true)]
    [Parameter(ParameterSetName = "Delete", Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(1, 7300)]
    [int]$BackupRetentionDays
)

# Set and initialise basic things
$Today = Get-Date
$TodayFormatted = Get-Date -UFormat "%Y.%m.%d"
$MachineName = $env:COMPUTERNAME
$BackupDestinationPersonalized = "$BackupDestination\$MachineName"
$BackupDestinationPersonalizedDated = "$BackupDestinationPersonalized\$TodayFormatted"
$LogPathPersonalized = "$LogPath\$MachineName"
$Stardate = "{0:F3}" -f (((Get-Date) - (Get-Date "1/1/2000Z")).TotalDays / 0.36525)
If ($Volumes -ne $null) {
    #$VolumeTargets = Get-WBVolume -AllVolumes | Where-Object {$_.mountpath -match ($Volumes -join "|")}
    $VolumesSanitized = ($Volumes -replace '(\w)(\W)', '$1')
    $VolumesForLog = ($VolumesSanitized -replace '(\w)', '$1:')
}
If ($BackupRetentionDays -ne $null) {
    $BackupRetentionTargetDate = (Get-Date).AddDays( - $BackupRetentionDays)
    If ($DeleteOld -eq $true ) {
        $BackupDeletionTargets = Get-ChildItem -Path $BackupDestinationPersonalized -Directory -Force | Where-Object { $_.CreationTime -lt $BackupRetentionTargetDate }
    }
    If ($ArchiveOld -eq $true) {
        $ArchiveDestinationPersonalized = "$ArchiveDestination\$MachineName"
        If ($ArchiveRetentionDays -eq 0) {
            $ArchiveRetentionDefaulted = $true
            $ArchiveRetentionDays = $BackupRetentionDays * 2
        }
        $ArchiveRetentionTargetDate = (Get-Date).AddDays( - $ArchiveRetentionDays)
        $ArchiveDeletionTargets = Get-ChildItem -Path $ArchiveDestinationPersonalized -Directory -Force | Where-Object { $_.CreationTime -lt $ArchiveRetentionTargetDate }
        $BackupRetentionTargetDate = (Get-Date).AddDays( - $BackupRetentionDays)
        $BackupArchiveTargets = Get-ChildItem -Path $BackupDestinationPersonalized -Directory -Force | Where-Object { $_.CreationTime -lt $BackupRetentionTargetDate }
    }
}
Function Test-Paths {
    New-Item -ItemType Directory "$BackupDestinationPersonalizedDated"
    New-Item -ItemType Directory "$LogPathPersonalized"
    If ($ArchiveOld -eq $true) {
        New-Item -ItemType Directory "$ArchiveDestinationPersonalized"
    }
}

Function Write-LogHeader {
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value "Captain's log, Stardate $Stardate`n"
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value "Backup options set as follows:"
    If ($BackupDestinationInvalid -eq $True) {
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Provided Backup Destination Invalid"
    }
    Else {
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Backup Destination - $BackupDestinationPersonalized"
    }
    If ($Volumes -ne $null) {
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Volume Backup - $VolumesForLog"
    }
    Else {
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Bare Metal Backup (default)"
    }
    If ($DeleteOld -eq $true) {
        $BackupDeletionTargetsCount = $BackupDeletionTargets.Count
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Backup Retention Period - $BackupRetentionDays Days"
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"$BackupDeletionTargetsCount backups to be deleted"
    }
    If ($ArchiveOld -eq $true) {
        $ArchiveDeletionTargetsCount = $ArchiveDeletionTargets.Count
        $BackupArchiveTargetsCount = $BackupArchiveTargets.Count
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"Archival Mode set:"
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"Local Retention Period - $BackupRetentionDays Days "
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"Archive Destination - $ArchiveDestination"
        If ($ArchiveRetentionDefaulted -eq $true) {
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"Archive Retention - Defaulted to $ArchiveRetentionDays Days"
        }
        Else {
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"Archive Retention Period - $ArchiveRetentionDays Days"
        }
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"$ArchiveDeletionTargetsCount backups to be deleted from Archive Destination" 
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t`t"$BackupArchiveTargetsCount archived backups to be moved to Archive Destination"
    }
    Else { 
        Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `t"No archival options set"
    }
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n`n
}

Function Start-BareMetalBackup {
    $WBPolicy = New-WBPolicy
    If ($BackupDestination -like "*\\*") {
        $BackupLocation = New-WBBackupTarget -NetworkPath "$BackupDestinationPersonalizedDated"
    }
    ElseIf ($BackupDestination -like "*:\*") {
        $BackupLocation = New-WBBackupTarget -FilePath "$BackupDestinationPersonalizedDated"
    }
    Else {
        $BackupDestinationInvalid = $true
    }
    Add-WBBackupTarget -Policy $WBPolicy -Target $BackupLocation
    Set-WBVssBackupOption -Policy $WBPolicy -VssFullBackup
    Add-WBBareMetalRecovery -Policy $WBPolicy
    Add-WBSystemState -Policy $WBPolicy
    $CurrentTime = Get-date -format u
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backup started $CurrentTime`n"
    Start-WBBackup -Policy $WBPolicy -Force | Out-File -Encoding utf8 -Append -NoClobber -FilePath "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt"
    $CurrentTime = Get-date -format u
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backup completed $CurrentTime"
}

Function Start-VolumeBackup {
    #Volume Backup using Windows Server Backup does not seem reliable - trying using Vhd2disk
    #Add-WBVolume -Policy $WBPolicy -Volume $VolumeTargets
    $CurrentTime = Get-date -format u
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backup started $CurrentTime`n"
    #Start-WBBackup -Policy $WBPolicy -Force | Out-File -Encoding UTF8 -Append -NoClobber -FilePath "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt"
    ForEach ($Volume in $VolumesForLog) {
        $VolumeSanitized = ($Volume -replace '(\w)(\W)', '$1')
        Disk2Vhd $Volume "$BackupDestinationPersonalizedDated\$VolumeSanitized.vhdx" -accepteula
    }
    $CurrentTime = Get-date -format u
    Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backup completed $CurrentTime"
}

Function Move-LocalBackups {
    If ($ArchiveOld -eq $true) {
        If ($ArchiveDeletionTargets -eq $null) {
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Archive retention period not exceeded - No archived backups will be deleted"
        }
        Else {
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Deleting backups from Archive exceeding Archive Retention Period - $CurrentTime"
            Remove-Item -Recurse -Force -Path $ArchiveDeletionTargets.FullName | Out-File -Encoding utf8 -Append -NoClobber -FilePath "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt"
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Archive backups deleted - $CurrentTime"
        }
        If ($BackupArchiveTargets -eq $null) {
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Retention period not exceeded - No backups will be archived"
        }
        Else {
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Archiving Backups - $CurrentTime"
            ForEach ($Target in $BackupArchiveTargets) {
                $TargetPath = $Target.FullName
                $TargetName = $Target.Name
                $ArchiveTopfolder = "$ArchiveDestinationPersonalized\$TargetName"
                robocopy $TargetPath $ArchiveTopFolder /MOVE /E /MT:128 /COPY:DATSO /R:5 /W:1 /NP /NFL /NDL | Out-File -Encoding utf8 -Append -NoClobber -FilePath "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt"
            }
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backups Archived - $CurrentTime"
        }    
    }
    If ($DeleteOld -eq $true) {
        Write-Host `n"Running backup deletion`n"
        If ($BackupDeletionTargets -eq $null) {
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Retention period not exceeded - No backups will be deleted"
        }
        Else {
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Deleting backups exceeding Backup Retention Period - $CurrentTime"
            Remove-Item -Recurse -Force -Path $BackupDeletionTargets.FullName | Out-File -Encoding utf8 -Append -NoClobber -FilePath "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt"
            $CurrentTime = Get-Date -Format u
            Add-Content -Path "$LogPathPersonalized\ServerBackup.$TodayFormatted.txt" -Encoding utf8 -Value `n"Backups Deleted - $CurrentTime"
        }
    }    
}

# Do the Needful
Test-Paths
Write-LogHeader
Move-LocalBackups
If ($Volumes -ne $null) {
    Start-VolumeBackup
}
Else {
    Start-BareMetalBackup
}