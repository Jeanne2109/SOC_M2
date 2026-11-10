<?php
require_once 'config.inc';
require_once 'util.inc';
require_once '/usr/local/opnsense/mvc/script/load_phalcon.php';
$m = new OPNsense\WazuhAgent\WazuhAgent();
$m->logcollector->syslog_programs = 'filterlog';
$m->serializeToConfig(false, true);
OPNsense\Core\Config::getInstance()->save();
echo "SYSLOG_PROGRAMS_OK\n";
