<?php
require_once 'config.inc';
require_once 'util.inc';
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';
use OPNsense\Core\Config;
use OPNsense\Cron\Cron;
use OPNsense\IDS\IDS;

// Pas de dechargement materiel des cartes : Suricata doit voir les paquets complets
$cfg = &config_read_array('system');
$cfg['disablechecksumoffloading'] = '1';
$cfg['disablesegmentationoffloading'] = '1';
$cfg['disablelargereceiveoffloading'] = '1';
write_config('SOC lab : dechargement materiel desactive pour Suricata');

$ids = new IDS();
$ids->general->enabled = '1';
$ids->general->mode = 'pcap';            // detection seule (IDS)
$ids->general->promisc = '0';
$ids->general->interfaces = 'wan';
$ids->general->homenet = '10.10.20.0/24,10.10.30.0/24';
$ids->general->MPMAlgo = 'hs';
foreach (['emerging-scan.rules', 'emerging-exploit.rules', 'emerging-malware.rules', 'emerging-policy.rules',
          'emerging-dos.rules', 'ciarmy.rules', 'drop.rules', 'compromised.rules'] as $f) {
    $ids->getFileNode($f)->enabled = '1';
}
if ($ids->general->UpdateCron->isEmpty()) {
    $cron = new Cron();
    $ids->general->UpdateCron = $cron->newDailyJob('IDS', 'ids update', 'ids rule updates', '*', '0');
    $cron->serializeToConfig();
}
$msgs = $ids->performValidation();
foreach ($msgs as $m) { echo "VALIDATION: " . $m->getField() . " " . $m->getMessage() . "\n"; }
$ids->serializeToConfig(false, true);
Config::getInstance()->save();
echo "IDS_CONFIG_OK\n";
