# Runbook: TLS Certificate Renewal

**Scope:** renewing and deploying TLS certificates before they expire. An expired cert is a self-inflicted outage.

## Prevent surprises (standing monitoring)

- Daily: `network/tls_audit.py -f endpoints.txt --warn 30 --crit 7` (exit code feeds monitoring:
  WARNING ≤ 30 days, CRITICAL ≤ 7 days).
- Prometheus blackbox alerts `TlsCertExpiringSoon` (21d) and `TlsCertExpiringCritical` (7d)
  (`observability/prometheus/rules/endpoint-alerts.yml`).
- Keep an inventory of every cert: host, SANs, issuer, expiry, where the private key lives, auto vs. manual.

## Automated renewal (preferred — ACME / Let's Encrypt)

- **Kubernetes:** cert-manager with a `ClusterIssuer` renews automatically; Ingress references the TLS
  secret (`containers/kubernetes/web-app/ingress.yaml`). Verify: `kubectl get certificate -A` shows
  `READY=True` and a future renewal time.
- **nginx / standalone:** certbot with the webroot or DNS-01 challenge on a systemd timer. The reverse
  proxy already serves `/.well-known/acme-challenge/` (`nginx/conf.d/reverse-proxy.conf`).
  Verify the timer: `systemctl list-timers | grep certbot` and `certbot certificates`.

After any renewal, reload (don't restart) the service: `nginx -t && systemctl reload nginx`.

## Manual renewal (commercial CA / internal CA)

1. Generate a key and CSR on the target host (keep the private key on the host; never email it):
   ```bash
   openssl req -new -newkey rsa:2048 -nodes \
     -keyout shop.example.com.key \
     -out shop.example.com.csr \
     -subj "/CN=shop.example.com" \
     -addext "subjectAltName=DNS:shop.example.com,DNS:www.shop.example.com"
   ```
2. Submit the CSR to the CA; complete domain validation.
3. Install the issued cert **with the full chain** (leaf + intermediates) as `fullchain.pem`.
4. Set permissions: key `600 root:root` (or the service user), cert `644`.
5. Test and reload: `nginx -t && systemctl reload nginx` (or the app's reload).

## Verify after deployment

- [ ] `network/tls_audit.py shop.example.com:443 --protocols` — trusted chain, correct SANs, TLS 1.2/1.3
      only (no TLS 1.0/1.1), expiry well in the future.
- [ ] Browser shows a valid chain (no "incomplete chain" — the #1 manual-renewal mistake).
- [ ] OCSP stapling working if enabled.

## Internal CA / private PKI note

Internal CAs need the same discipline plus CA-cert distribution (the AD-joined fleet trusts the enterprise
root automatically; Linux hosts need it in the trust store). Rotate the intermediate well before the root,
and never let the root CA key sit on a networked host.
