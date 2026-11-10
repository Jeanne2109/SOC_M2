<?php
require_once 'config.inc';
require_once 'util.inc';
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';
$m = new OPNsense\WazuhAgent\WazuhAgent();
$m->general->enabled = '1';
$m->general->server_address = '10.10.30.10';
$m->general->agent_name = 'opnsense';
$m->logcollector->suricata_eve_log = '1';
foreach ($m->performValidation() as $v) { echo "VALIDATION: " . $v->getField() . " " . $v->getMessage() . "\n"; }
$m->serializeToConfig(false, true);
OPNsense\Core\Config::getInstance()->save();
echo "WAZUH_AGENT_CONFIG_OK\n";
