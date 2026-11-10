# Etape 0 : verifie les images, decompresse l'ISO OPNsense, cree la cle SSH du labo
. (Join-Path $PSScriptRoot "lib.ps1")

New-Item -ItemType Directory -Force $Images, $VmDir, $Secrets, $Shots | Out-Null

# Verification des empreintes publiees par les editeurs
$bz2 = "$OpnIso.bz2"
$expected = (Select-String -Path (Join-Path $Images "OPNsense-$OpnVersion-checksums-amd64.sha256") -Pattern ([regex]::Escape((Split-Path $bz2 -Leaf)))).Line -replace '.*= ', ''
$actual = (Get-FileHash $bz2 -Algorithm SHA256).Hash
if ($actual -ne $expected.ToUpper()) { throw "Empreinte OPNsense invalide" }
Write-Host "OPNsense : empreinte SHA256 OK"

$expected = ((Get-Content "$WazuhOva.sha512" -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash $WazuhOva -Algorithm SHA512).Hash
if ($actual -ne $expected.ToUpper()) { throw "Empreinte Wazuh invalide" }
Write-Host "Wazuh : empreinte SHA512 OK"

# Decompression de l'ISO (bz2) avec Python
if (-not (Test-Path $OpnIso)) {
    python -I -c "import bz2,shutil,sys; shutil.copyfileobj(bz2.open(sys.argv[1]), open(sys.argv[2],'wb'), 1<<20)" $bz2 $OpnIso
    Write-Host "ISO OPNsense decompressee"
}

# Cle SSH du labo (sans phrase de passe, usage local uniquement)
# ECDSA P-256 : la VM Wazuh est en mode FIPS et refuse les cles Ed25519
if (-not (Test-Path $SshKey)) {
    ssh-keygen -q -t ecdsa -b 256 -N "" -C "soc-lab" -f $SshKey   # -N "" : aucune phrase de passe (PowerShell 7)
    Write-Host "Cle SSH creee : $SshKey"
}

# Mots de passe du labo, generes une fois
$credFile = Join-Path $Secrets "lab-credentials.txt"
if (-not (Test-Path $credFile)) {
    $chars = [char[]]'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $pw = -join (1..16 | ForEach-Object { $chars | Get-Random })
    @(
        "# Identifiants du labo Projet 1 - usage local uniquement",
        "opnsense_root=$pw",
        "wazuh_vm_user=wazuh-user (mot de passe par defaut de l'OVA, a changer)",
        "wazuh_dashboard=admin (mot de passe par defaut de l'OVA, a changer)"
    ) | Set-Content $credFile
    Write-Host "Identifiants ecrits dans $credFile"
}
