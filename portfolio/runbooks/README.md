# runbooks

Operational runbooks — the decisions and steps for the moments that matter, written so an on-call engineer
can follow them under pressure. Each ties back to the tools in this repository.

| Runbook | When you reach for it |
|---|---|
| `incident-response.md` | Suspected compromise, malware, data exposure (NIST SP 800-61 lifecycle). |
| `backup-and-restore.md` | Verifying backups and performing restores (3-2-1, test-restore discipline). |
| `patch-management.md` | Routine and emergency (KEV) patching without self-inflicted outages. |
| `disaster-recovery.md` | Loss of a host, cluster or site — recovery order and failback. |
| `certificate-renewal.md` | Renewing TLS before expiry; automated (ACME/cert-manager) and manual. |
| `user-onboarding-offboarding.md` | Joiner/mover/leaver — least privilege in, complete revocation out. |
