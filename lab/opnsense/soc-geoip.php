<?php
// ER2 : alias GeoIP PAYS_RISQUE (Chine, Coree du Nord, Roumanie) et regle flottante qui le bloque
// sur le WAN, journalisee (le journal du pare-feu remonte a Wazuh par l'agent d'OPNsense).
// Prerequis : URL GeoLite2 (cle MaxMind de l'utilisateur) saisie dans Firewall > Aliases > GeoIP settings.
// Ensuite : /usr/local/opnsense/scripts/filter/download_geoip.py, configctl filter refresh_aliases, configctl filter reload
//
// Ordre important : la regle (configuration "legacy", write_config) d'abord, puis l'alias (modele MVC)
// apres rechargement. Dans l'ordre inverse, write_config reecrivait la configuration lue au demarrage
// et effacait l'alias tout juste cree (constate le 09/11).
require_once 'config.inc';
require_once 'util.inc';
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';

// 1. Regle flottante
$rules = &config_read_array('filter', 'rule');
$present = false;
foreach ($rules as $r) {
    if (($r['descr'] ?? '') == 'ER2 blocage pays a risque') { $present = true; }
}
if (!$present) {
    array_unshift($rules, array('type' => 'block', 'interface' => 'wan', 'floating' => 'yes', 'quick' => '1',
        'direction' => 'in', 'ipprotocol' => 'inet',
        'source' => array('address' => 'PAYS_RISQUE'), 'destination' => array('any' => '1'),
        'log' => '1', 'descr' => 'ER2 blocage pays a risque'));
    write_config('SOC lab : ER2 regle flottante PAYS_RISQUE');
    echo "REGLE_CREEE\n";
}

// 2. Alias GeoIP, sur la configuration rechargee depuis le disque
OPNsense\Core\Config::getInstance()->forceReload();
$mdl = new OPNsense\Firewall\Alias();
foreach ($mdl->aliases->alias->iterateItems() as $a) {
    if ((string)$a->name == 'PAYS_RISQUE') { echo "ALIAS_DEJA_PRESENT\n"; exit(0); }
}
$a = $mdl->aliases->alias->Add();
$a->enabled = '1';
$a->name = 'PAYS_RISQUE';
$a->type = 'geoip';
$a->content = "CN\nKP\nRO";
$a->description = 'ER2 - pays a risque (Chine, Coree du Nord, Roumanie)';
$mdl->serializeToConfig(false, true);
OPNsense\Core\Config::getInstance()->save();
echo "ALIAS_CREE\n";
