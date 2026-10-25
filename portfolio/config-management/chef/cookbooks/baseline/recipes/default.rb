# Cookbook:: baseline
# Recipe:: default
#
# Cross-platform host baseline: chrony NTP, an admin group with sudo, SSH hardening (validated),
# a login banner and core sysctl settings. Attributes override the defaults.

chrony_conf = platform_family?('debian') ? '/etc/chrony/chrony.conf' : '/etc/chrony.conf'
chrony_service = platform_family?('debian') ? 'chrony' : 'chronyd'
ssh_service = platform_family?('debian') ? 'ssh' : 'sshd'

package 'chrony'

template chrony_conf do
  source 'chrony.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
  variables(servers: node['baseline']['ntp_servers'])
  notifies :restart, "service[#{chrony_service}]", :delayed
end

service chrony_service do
  action %i(enable start)
end

group node['baseline']['admin_group'] do
  action :create
end

file "/etc/sudoers.d/10-#{node['baseline']['admin_group']}" do
  content "%#{node['baseline']['admin_group']} ALL=(ALL:ALL) ALL\n"
  owner 'root'
  group 'root'
  mode '0440'
  verify 'visudo -cf %{path}'
end

directory '/etc/ssh/sshd_config.d' do
  owner 'root'
  group 'root'
  mode '0755'
end

template '/etc/ssh/sshd_config.d/10-hardening.conf' do
  source 'sshd_hardening.conf.erb'
  owner 'root'
  group 'root'
  mode '0600'
  variables(
    permit_root: node['baseline']['permit_root_login'],
    admin_group: node['baseline']['admin_group']
  )
  verify 'sshd -t -f %{path}'
  notifies :reload, "service[#{ssh_service}]", :delayed
end

service ssh_service do
  action %i(enable start)
end

file '/etc/issue.net' do
  content "Authorized access only. Activity is monitored and logged.\n"
  owner 'root'
  group 'root'
  mode '0644'
end

node['baseline']['sysctl'].each do |key, value|
  # Requires the 'sysctl' cookbook (Chef supermarket) for the sysctl resource.
  sysctl key do
    value value
  end
end
