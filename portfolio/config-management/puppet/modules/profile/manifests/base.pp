# @summary Baseline configuration applied to every managed Linux node.
#
# Manages NTP (chrony), an admin group with passwordless-free sudo, SSH hardening via a validated
# drop-in, a login banner and core sysctl hardening. Cross-distribution (Debian/RedHat families).
#
# @param ntp_servers      NTP servers for chrony.
# @param admin_group      Group granted sudo.
# @param permit_root      PermitRootLogin value for sshd.
# @param manage_firewall  Whether to ensure the host firewall service is running.
class profile::base (
  Array[String[1]] $ntp_servers   = ['0.pool.ntp.org', '1.pool.ntp.org'],
  String[1]        $admin_group   = 'ops',
  Enum['no', 'prohibit-password'] $permit_root = 'no',
  Boolean          $manage_firewall = true,
) {
  $chrony_conf = $facts['os']['family'] ? {
    'Debian' => '/etc/chrony/chrony.conf',
    default  => '/etc/chrony.conf',
  }
  $chrony_service = $facts['os']['family'] ? {
    'Debian' => 'chrony',
    default  => 'chronyd',
  }

  package { 'chrony':
    ensure => installed,
  }

  file { $chrony_conf:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('profile/chrony.conf.epp', { 'servers' => $ntp_servers }),
    require => Package['chrony'],
    notify  => Service[$chrony_service],
  }

  service { $chrony_service:
    ensure => running,
    enable => true,
  }

  group { $admin_group:
    ensure => present,
  }

  file { "/etc/sudoers.d/10-${admin_group}":
    ensure       => file,
    owner        => 'root',
    group        => 'root',
    mode         => '0440',
    content      => "%${admin_group} ALL=(ALL:ALL) ALL\n",
    validate_cmd => '/usr/sbin/visudo -cf %',
  }

  file { '/etc/ssh/sshd_config.d/10-hardening.conf':
    ensure       => file,
    owner        => 'root',
    group        => 'root',
    mode         => '0600',
    content      => epp('profile/sshd_hardening.conf.epp', {
        'permit_root'  => $permit_root,
        'admin_group'  => $admin_group,
    }),
    validate_cmd => '/usr/sbin/sshd -t -f %',
    notify       => Service['sshd'],
  }

  service { 'sshd':
    ensure => running,
    enable => true,
    name   => $facts['os']['family'] ? {
      'Debian' => 'ssh',
      default  => 'sshd',
    },
  }

  file { '/etc/issue.net':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "Authorized access only. Activity is monitored and logged.\n",
  }

  $sysctl = {
    'net.ipv4.conf.all.accept_redirects'  => '0',
    'net.ipv4.conf.all.send_redirects'    => '0',
    'net.ipv4.conf.all.accept_source_route' => '0',
    'net.ipv4.conf.all.rp_filter'         => '1',
    'net.ipv4.tcp_syncookies'             => '1',
    'kernel.randomize_va_space'           => '2',
  }
  $sysctl.each |$key, $value| {
    sysctl { $key:
      ensure => present,
      value  => $value,
    }
  }

  if $manage_firewall {
    $firewall_service = $facts['os']['family'] ? {
      'Debian' => 'ufw',
      default  => 'firewalld',
    }
    service { $firewall_service:
      ensure => running,
      enable => true,
    }
  }
}
