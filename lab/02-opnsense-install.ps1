# Etape 2 : installation d'OPNsense sur le disque, pilotee au clavier de la console
# Les delais sont larges : sous Hyper-V, VirtualBox est lent (copie du systeme : 15 a 30 min).
# Une capture d'ecran est prise a chaque etape dans captures\ pour controle.
. (Join-Path $PSScriptRoot "lib.ps1")

function Step([string]$Label, [scriptblock]$Keys, [int]$Wait) {
    & $Keys
    Start-Sleep $Wait
    Save-Screen $VmOpn $Label | Out-Null
}

# Le systeme live demarre (2 a 4 min) et affiche "login:"
Step "01-login"     { Send-Line $VmOpn "installer"; Start-Sleep 3; Send-Line $VmOpn "opnsense" } 12  # compte d'installation publie par OPNsense
Step "02-keymap"    { Send-Key $VmOpn Enter } 4                                   # clavier US par defaut
Step "03-ufs"       { Send-Key $VmOpn Down; Send-Key $VmOpn Enter } 5               # Install (UFS)
Step "04-disque"    { Send-Key $VmOpn Down; Send-Key $VmOpn Enter } 4               # ada0, disque de 30 Go
Step "05-swap"      { Send-Key $VmOpn Enter } 4                                     # swap recommande
Step "06-confirmer" { Send-Key $VmOpn Enter } 60                                    # effacement de ada0 (disque neuf)

Write-Host "Copie en cours : surveiller captures\SOC-OPNsense-06-confirmer.png puis lancer 02b-opnsense-fin.ps1"
