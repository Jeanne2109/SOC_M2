# Etape 2b : premiere configuration d'OPNsense depuis la console (apres 02-opnsense-install.ps1)
#  - interfaces : WAN = em0 (192.168.56.2), SERVEURS = em1 (10.10.20.1), OUTILS = em2 (10.10.30.1)
#  - SSH par cle (root), acces admin SSH/HTTPS depuis le PC hote uniquement
. (Join-Path $PSScriptRoot "lib.ps1")

$pw  = ((Get-Content (Join-Path $Secrets "lab-credentials.txt")) -match '^opnsense_root=') -replace '^opnsense_root=', ''
$pub = (Get-Content "$SshKey.pub" -Raw).Trim()
function Answer([string[]]$Lines, [int]$Wait = 2) { foreach ($l in $Lines) { Send-Line $VmOpn $l; Start-Sleep $Wait } }

# Connexion root puis menu 1 : affectation des interfaces
Answer @("root", $pw) 4
Answer @("1", "n", "n", "em0", "em1", "em2", "", "y") 3
Start-Sleep 40

# Menu 2 : adresses. Reponses : DHCP non, adresse, masque, passerelle vide, IPv6 non, (DHCP serveur non), HTTPS garde, certificat garde, acces GUI garde
Answer @("2", "3", "n", $Ip.OpnWan, "24", "", "n", "", "n", "n", "n"); Start-Sleep 25
Answer @("2", "1", "n", $Ip.OpnSrv, "24", "", "n", "", "n", "n", "n", "n"); Start-Sleep 25
Answer @("2", "2", "n", $Ip.OpnOutils, "24", "", "n", "", "n", "n", "n", "n"); Start-Sleep 25

# Menu 8 : shell. Le shell root est csh : on passe en sh pour le bloc << FIN
$php = @'
<?php
require_once 'config.inc';
require_once 'util.inc';
$wan = &config_read_array('interfaces', 'wan');
unset($wan['blockpriv'], $wan['blockbogons']);
$lan = &config_read_array('interfaces', 'lan');
$lan['descr'] = 'SERVEURS';
$opt = &config_read_array('interfaces', 'opt1');
$opt['descr'] = 'OUTILS';
$opt['enable'] = '1';
$ssh = &config_read_array('system', 'ssh');
$ssh['enabled'] = 'enabled';
$ssh['permitrootlogin'] = '1';
unset($ssh['passwordauth']);
$users = &config_read_array('system', 'user');
foreach ($users as &$u) {
    if ($u['name'] == 'root') {
        $u['authorizedkeys'] = base64_encode('__KEY__');
    }
}
$rules = &config_read_array('filter', 'rule');
foreach (array('22' => 'SSH', '443' => 'HTTPS') as $port => $nom) {
    $rules[] = array('type' => 'pass', 'interface' => 'wan', 'ipprotocol' => 'inet',
        'protocol' => 'tcp', 'source' => array('address' => '192.168.56.1'),
        'destination' => array('network' => '(self)', 'port' => $port),
        'descr' => "Admin $nom depuis le PC hote");
}
write_config('SOC lab : SSH, acces admin WAN, noms des interfaces');
echo "CONFIG_OK\n";
'@ -replace '__KEY__', $pub

Answer @("8", "sh") 3
Send-Line $VmOpn "cat > /root/soc-setup.php <<'FIN'"
foreach ($line in $php -split "`r?`n") { Send-Line $VmOpn $line; Start-Sleep -Milliseconds 300 }
Send-Line $VmOpn "FIN"; Start-Sleep 2
Send-Line $VmOpn "php /root/soc-setup.php && mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$pub' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
Start-Sleep 10

# Redemarrage : arrete les clients DHCP lances au premier demarrage (affectation automatique)
Send-Line $VmOpn "reboot"
Write-Host "Redemarrage d'OPNsense. Ensuite : ssh root@$($Ip.OpnWan) et https://$($Ip.OpnWan)"
