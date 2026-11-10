# Relance les VMs du labo (OPNsense d'abord, puis Wazuh, puis les serveurs et Kali).
# Une VM mise en pause par pause.ps1 reprend en quelques secondes, dans l'etat ou elle etait.
. (Join-Path $PSScriptRoot "lib.ps1")

foreach ($vm in $VmOpn, $VmWazuh, "SOC-IA", "SOC-SRV-WEB", "SOC-SRV-WIN", "SOC-Kali") {
    if ((Test-Vm $vm) -and -not (Test-VmRunning $vm)) {
        Write-Host "Reprise de $vm..."
        VBox startvm $vm --type headless
    }
}
# Apres une reprise, l'horloge des VMs est en retard : on la resynchronise
Invoke-SshScript "root@$($Ip.OpnWan)" "ntpdate -u pool.ntp.org >/dev/null 2>&1 || true" | Out-Null
Write-Host "Labo relance : OPNsense https://$($Ip.OpnWan) | Wazuh https://$($Ip.WazuhAdmin)"
