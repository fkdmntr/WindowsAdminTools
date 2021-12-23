Param([String]$TargetSystem = ($Env:COMPUTERNAME))

function Get-ComputerInfo{
    Param($TargetSystem)
    $TargetSystemIPv4 = Resolve-DnsName -Name $TargetSystem -Type A
    if ($null -ne $TargetSystemIPv4){
        $Online = Test-Connection $TargetSystemIPv4.IPAddress
        if ($null -ne $Online)
        {
            # ComputerSystem info
            $SystemInfo = Get-CimInstance Win32_ComputerSystem -Computer $TargetSystem

            # OS info
            $OSInfo = Get-CimInstance Win32_OperatingSystem -Computer $TargetSystem

            # Serial No
            $BiosInfo = Get-CimInstance Win32_BIOS -Computer $TargetSystem

            # CPU Info
            $CPUInfo = Get-CimInstance Win32_Processor -Computer $TargetSystem

            # Mobo Info
            $MoboInfo = Get-CimInstance Win32_Baseboard -ComputerName $TargetSystem

            # Create Computer Object
            $System = "" | Select-Object Name,Domain,Model,MachineSN,OS,Build,WindowsSN,Uptime,Mobo,CPU,RAM,Disk
            $System.Name = $SystemInfo.Name
            $System.Domain = $SystemInfo.Domain
            $System.Model = "$($SystemInfo.SystemFamily) $($SystemInfo.Model)"
            $System.MachineSN = $BiosInfo.SerialNumber
            $System.OS = $OSInfo.Caption
            $System.Build = $OSInfo.BuildNumber
            $System.WindowsSN = $OSInfo.SerialNumber
            $System.uptime = (Get-Date) - ($OSInfo.LastBootUpTime)
            $System.uptime = "$($System.uptime.Days) days, $($System.uptime.Hours) hours," +` " $($System.uptime.Minutes) minutes" 
            $System.Mobo = "$($MoboInfo.Manufacturer) $($MoboInfo.Product)"
            $System.CPU = $CPUInfo.Name
            $System.RAM = "{0:n2} GB" -f ($SystemInfo.TotalPhysicalMemory/1gb)
            $System.Disk = Get-DriveInfo $TargetSystem
            #Return System Object"
            $System
        }
        else {Write-Host "Error: Could not ping $TargetSystem" -ForegroundColor Red}
    }
    Else {Write-Host "Could not resolve $TargetSystem IPv4 address" -ForegroundColor Red}
}

function Get-DriveInfo{
    Param($TargetSystem)
    # Get disk sizes
    $logicalDisk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $TargetSystem
    foreach($disk in $logicalDisk)
    {
        $diskObj = "" | Select-Object Disk,Size,FreeSpace
        $diskObj.Disk = $disk.DeviceID
        $diskObj.Size = "{0:n0} GB" -f (($disk | Measure-Object -Property Size -Sum).sum/1gb)
        $diskObj.FreeSpace = "{0:n0} GB" -f (($disk | Measure-Object -Property FreeSpace -Sum).sum/1gb)

        $text = "{0}  {1}  Free: {2}" -f $diskObj.Disk,$diskObj.size,$diskObj.Freespace
        $msg += $text + [char]13 + [char]10 
    }
    $msg
}
# Main - run all the functions
Get-ComputerInfo ($TargetSystem)