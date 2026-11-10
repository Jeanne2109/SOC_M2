<?php
require_once 'config.inc';
require_once 'util.inc';
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';
$ids = new OPNsense\IDS\IDS();
$ids->getFileNode('soc-local.rules')->enabled = '1';
$ids->serializeToConfig(false, true);
OPNsense\Core\Config::getInstance()->save();
echo "SOC_RULES_ENABLED\n";
