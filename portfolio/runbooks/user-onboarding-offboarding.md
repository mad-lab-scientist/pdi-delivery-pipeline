# Runbook: User Onboarding & Offboarding

**Scope:** joiner/mover/leaver (JML) for staff accounts across AD, Linux and SaaS.
**Principle:** least privilege on the way in; prompt, complete revocation on the way out. Offboarding is
a security control — stale enabled accounts are a top breach vector.

## Onboarding (joiner)

1. **Ticket & approval:** role, manager, start date, access profile (which groups). Manager approves.
2. **Create the account:**
   - AD: `identity/active-directory/Import-ADUsersFromCsv.ps1` (bulk) or `New-ADUser` (single). Place in
     the right OU (`identity/active-directory/ou-structure.psd1`); add to role groups, not direct ACLs.
     Account is created **disabled** until the start date, or enabled with a handover file for the temp
     password delivered out-of-band.
   - Linux: access flows from AD group membership via SSSD (`identity/linux/join-ad-domain.sh` with
     `--allow-groups`), so adding the user to the right AD group is all that's needed — no local accounts.
3. **Least privilege:** grant the role's standard access only. Admin/Tier-0 access is a separate,
   separately-approved request (tiered model in `ou-structure.psd1`).
4. **MFA:** enforce MFA enrollment on first logon. Verify (`Get-ADHealthReport.ps1` flags console users
   without MFA).
5. **Record** what was granted in the ticket for the eventual access review and offboarding.

## Mover (role change)

- Add the new role's groups; **remove the old role's groups** (the common miss — access accretes over
  careers into toxic combinations). Re-run an access review for the user after the change.

## Offboarding (leaver) — do within the agreed SLA (same day for involuntary)

1. **Disable, don't delete** (preserves audit trail and mailbox/data):
   - AD: `Disable-ADAccount`; reset the password to a random value; move to the Disabled OU.
   - Revoke sessions/tokens: Kerberos (`klist purge` is client-side; rely on disable + password reset),
     and revoke OAuth/SaaS tokens.
2. **Revoke secondary access:** SSH keys (`linux/common/user-audit.sh` to find them), API tokens, VPN,
   service-account shared credentials the person knew (rotate those).
3. **Reclaim:** licenses, hardware, building access. Forward email/transfer file ownership per policy.
4. **Privileged accounts:** if the leaver had admin/Tier-0, rotate the credentials they could have known
   and review for any accounts they created.
5. **Delete** after the retention period (e.g. 30–90 days), per policy — not immediately.

## Verify offboarding (the checklist that prevents the next breach)

- [ ] Account disabled and password reset; cannot authenticate.
- [ ] Removed from all privileged groups.
- [ ] SSH keys, API tokens, VPN access revoked.
- [ ] Shared/service credentials the person knew have been rotated.
- [ ] SaaS/IdP access removed (SSO disable covers most; check break-glass local accounts).
- [ ] Ticket closed with the completed checklist attached.

## Periodic access review (quarterly)

Run `identity/active-directory/Get-ADHealthReport.ps1` and `linux/common/user-audit.sh`; review
privileged group membership, stale accounts (`Disable-StaleADAccounts.ps1 -WhatIf`), accounts with
`PasswordNeverExpires`, and anyone whose access no longer matches their role.
