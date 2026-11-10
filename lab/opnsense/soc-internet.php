<?php
require_once 'config.inc';
require_once 'util.inc';
$inet = &config_read_array('interfaces', 'opt2');
$inet['if'] = 'em3';
$inet['descr'] = 'INTERNET';
$inet['enable'] = '1';
$inet['ipaddr'] = 'dhcp';
$rules = &config_read_array('filter', 'rule');
$rules[] = array('type' => 'pass', 'interface' => 'opt1', 'ipprotocol' => 'inet',
    'source' => array('network' => 'opt1'), 'destination' => array('any' => '1'),
    'descr' => 'OUTILS vers tout (labo)');
write_config('SOC lab : interface INTERNET (NAT VirtualBox) et sortie du VLAN Outils');
echo "CONFIG_OK\n";
