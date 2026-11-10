# Met en pause toutes les VMs du labo en sauvegardant leur etat (memoire comprise).
# A preferer a l'arret : sous Hyper-V, un demarrage complet prend jusqu'a 30 min par VM
# (lecture du noyau par le BIOS), la reprise d'un etat sauvegarde quelques secondes.
. (Join-Path $PSScriptRoot "lib.ps1")

foreach ($vm in "SOC-Kali", "SOC-SRV-WEB", "SOC-SRV-WIN", "SOC-IA", $VmWazuh, $VmOpn) {
    if (Test-VmRunning $vm) {
        Write-Host "Sauvegarde de l'etat de $vm..."
        VBox controlvm $vm savestate
    }
}
Write-Host "Labo en pause. Relancer avec reprise.ps1"
