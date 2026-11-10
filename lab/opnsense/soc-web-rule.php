<?php
// Flux F1 de la matrice : WAN (any) -> SRV-WEB 10.10.20.20, 80/TCP
require_once 'config.inc';
require_once 'util.inc';
$rules = &config_read_array('filter', 'rule');
foreach ($rules as $r) {
    if (($r['descr'] ?? '') == 'F1 WAN vers SRV-WEB (HTTP)') { echo "DEJA_PRESENTE\n"; exit(0); }
}
$rules[] = array('type' => 'pass', 'interface' => 'wan', 'ipprotocol' => 'inet', 'protocol' => 'tcp',
    'source' => array('any' => '1'),
    'destination' => array('address' => '10.10.20.20', 'port' => '80'),
    'log' => '1',
    'descr' => 'F1 WAN vers SRV-WEB (HTTP)');
write_config('SOC lab : flux F1 WAN vers SRV-WEB');
echo "REGLE_F1_OK\n";
