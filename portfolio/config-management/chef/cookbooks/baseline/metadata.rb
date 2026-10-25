name 'baseline'
maintainer 'Pearson Cyber Defense'
maintainer_email 'security@example.com'
license 'Proprietary'
description 'Host baseline: NTP, sudo, SSH hardening, banner, sysctl'
version '1.0.0'
chef_version '>= 17.0'

supports 'ubuntu', '>= 22.04'
supports 'debian', '>= 12.0'
supports 'redhat', '>= 9.0'
supports 'rocky', '>= 9.0'

depends 'sysctl', '>= 1.0'

source_url 'https://github.com/mad-lab-scientist/pdi-delivery-pipeline'
