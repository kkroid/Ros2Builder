$ErrorActionPreference = 'Stop'
$log = "$env:TEMP\ros2_fw_setup.log"
Start-Transcript -Path $log -Force | Out-Null
try {
    Write-Host '== 1. 把"网络 2 / 以太网"切到 Private =='
    $profiles = Get-NetConnectionProfile
    $profiles | Format-Table -AutoSize Name, InterfaceAlias, NetworkCategory
    foreach ($p in $profiles) {
        if ($p.InterfaceAlias -eq '以太网') {
            Set-NetConnectionProfile -InterfaceAlias $p.InterfaceAlias -NetworkCategory Private
            Write-Host "set '$($p.InterfaceAlias)' -> Private"
        }
    }
    Write-Host ''
    Write-Host '== 2. 添加 Hyper-V WSL 防火墙规则 (UDP 7400-7600 from 192.168.3.0/24) =='
    $vmId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
    $ruleName = 'ROS2_FastDDS_LAN_Inbound'
    Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallHyperVRule -ErrorAction SilentlyContinue
    New-NetFirewallHyperVRule `
        -Name $ruleName `
        -DisplayName 'ROS2 FastDDS LAN Inbound (UDP 7400-7600 from 192.168.3.0/24)' `
        -VMCreatorId $vmId `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPorts 7400-7600 `
        -RemoteAddresses 192.168.3.0/24 `
        -Action Allow | Out-Null
    Get-NetFirewallHyperVRule -Name $ruleName | Format-List Name, DisplayName, Direction, Action, Protocol, LocalPorts, RemoteAddresses, VMCreatorId
    Write-Host ''
    Write-Host '== 3. 复核 =='
    Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -eq '以太网' } | Format-Table -AutoSize Name, InterfaceAlias, NetworkCategory
    Write-Host 'DONE_OK'
} catch {
    Write-Host "FAIL: $($_.Exception.Message)"
} finally {
    Stop-Transcript | Out-Null
}
