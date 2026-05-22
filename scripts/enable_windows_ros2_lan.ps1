#Requires -RunAsAdministrator
param(
    [string]$InterfaceAlias = "WLAN",
    [string]$RemoteSubnet = "192.168.1.0/24",
    [string]$Profile = "Private",
    [string]$UdpPorts = "7400-7600"
)

$ErrorActionPreference = "Stop"

$connectionProfile = Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias
if ($connectionProfile.NetworkCategory -ne $Profile) {
    Set-NetConnectionProfile -InterfaceAlias $InterfaceAlias -NetworkCategory $Profile
}

$rules = @(
    @{
        DisplayName = "ROS 2 DDS UDP Domain 0 ($InterfaceAlias)"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "UDP"
        LocalPort = $UdpPorts
        RemoteAddress = $RemoteSubnet
        Profile = $Profile
    },
    @{
        DisplayName = "ROS 2 LAN ICMPv4 ($InterfaceAlias)"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "ICMPv4"
        IcmpType = 8
        RemoteAddress = $RemoteSubnet
        Profile = $Profile
    }
)

foreach ($rule in $rules) {
    $existingRule = Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName
    }
    New-NetFirewallRule @rule | Out-Null
}

Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias |
    Select-Object Name, InterfaceAlias, NetworkCategory

Get-NetFirewallRule -DisplayName "ROS 2*($InterfaceAlias)" |
    Select-Object DisplayName, Enabled, Profile, Direction, Action
