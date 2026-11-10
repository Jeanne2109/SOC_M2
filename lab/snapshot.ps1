# Snapshot des VMs du labo, une par une : mise en veille -> snapshot -> reprise.
#   .\snapshot.ps1                       -> toutes les VMs du labo, nom date
#   .\snapshot.ps1 "nom"                 -> nom choisi
#   .\snapshot.ps1 "nom" SOC-Wazuh       -> une seule VM
# Pourquoi pas de snapshot "a chaud" (--live) : le 30/10, 4 snapshots a chaud simultanes (16 Go de
# memoire) ont sature la RAM du PC sous Hyper-V et fige Wazuh pendant 2 jours (VM devenue inaccessible).
# Restauration : VM eteinte ou en veille, VBoxManage snapshot <VM> restore "<nom>", puis startvm.
. (Join-Path $PSScriptRoot "lib.ps1")
$nom = if ($args.Count -ge 1) { $args[0] } else { "lab-{0:yyyyMMdd-HHmm}" -f (Get-Date) }
$vms = if ($args.Count -ge 2) { $args[1..($args.Count - 1)] } else { @($VmOpn, $VmWazuh, "SOC-SRV-WEB", "SOC-SRV-WIN", "SOC-IA", "SOC-Kali") }

foreach ($vm in $vms) {
    if (-not (Test-Vm $vm)) { continue }
    $etait = Test-VmRunning $vm
    if ($etait) { Write-Host "$vm : mise en veille..."; VBox controlvm $vm savestate }
    Write-Host "$vm : snapshot '$nom'..."
    VBox snapshot $vm take $nom --description "Labo configure et teste"
    if ($etait) { Write-Host "$vm : reprise"; VBox startvm $vm --type headless }
}
Write-Host "`nSnapshots pris : $nom"
