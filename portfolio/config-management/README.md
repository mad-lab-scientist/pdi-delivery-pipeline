# config-management

The same host baseline (chrony NTP, admin group + sudo, validated SSH hardening, login banner, sysctl)
expressed in both Puppet and Chef, to complement the Ansible roles in [`../ansible/`](../ansible/).

| Path | What it is |
|---|---|
| `puppet/modules/profile/` | `profile::base` class with EPP templates and `metadata.json`. Validated with `puppet parser validate` and `puppet epp validate`. |
| `chef/cookbooks/baseline/` | `baseline::default` recipe with attributes, ERB templates and `metadata.rb`. Ruby syntax-checked in CI. |

Both validate configuration before applying it (`visudo -cf`, `sshd -t`) so a bad render can't lock you out
or break the service.
