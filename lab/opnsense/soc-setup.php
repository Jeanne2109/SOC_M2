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
