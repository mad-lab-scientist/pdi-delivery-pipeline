default['baseline']['ntp_servers'] = ['0.pool.ntp.org', '1.pool.ntp.org']
default['baseline']['admin_group'] = 'ops'
default['baseline']['permit_root_login'] = 'no'
default['baseline']['sysctl'] = {
  'net.ipv4.conf.all.accept_redirects' => '0',
  'net.ipv4.conf.all.send_redirects' => '0',
  'net.ipv4.conf.all.accept_source_route' => '0',
  'net.ipv4.conf.all.rp_filter' => '1',
  'net.ipv4.tcp_syncookies' => '1',
  'kernel.randomize_va_space' => '2',
}
