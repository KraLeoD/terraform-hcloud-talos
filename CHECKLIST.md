# Implementation Checklist

Use this checklist to track your progress setting up GitOps, Cloudflare DNS, and Authentik on your Talos cluster.

## ✅ Phase 1: Initial Setup

- [ ] Repository cloned and updated
- [ ] Basic cluster deployed successfully
- [ ] ArgoCD installed and accessible
- [ ] Kubectl working with cluster
- [ ] Talosctl working with cluster

## ✅ Phase 2: SOPS Configuration

- [ ] `setup-sops.sh` executed successfully
- [ ] Age key generated at `.sops/age.agekey`
- [ ] `.sops.yaml` configuration file created
- [ ] Age key backed up to secure location (password manager, encrypted backup, etc.)
- [ ] `.gitignore` updated to exclude age key
- [ ] `SOPS_AGE_KEY_FILE` environment variable set

## ✅ Phase 3: Cloudflare Setup

- [ ] Cloudflare API token created with correct permissions:
  - [ ] Zone.Zone (Read)
  - [ ] Zone.DNS (Edit)
- [ ] Domain verified in Cloudflare
- [ ] API token tested and working

## ✅ Phase 4: Secret Generation

- [ ] `generate-secrets.sh` executed
- [ ] PostgreSQL passwords generated and encrypted
- [ ] Redis password generated and encrypted
- [ ] Authentik secret key generated and encrypted
- [ ] All secret files verified encrypted (check file contents)
- [ ] Encrypted backup created

## ✅ Phase 5: Application Manifest Setup

### External-DNS
- [ ] `external-dns-app.yaml` copied to `.demo/manifests/apps/external-dns/application.yaml`
- [ ] Domain filter updated with your domain
- [ ] Cloudflare token annotation added
- [ ] Resource limits adjusted if needed

### Authentik Dependencies
- [ ] `authentik-dependencies.yaml` copied to `.demo/manifests/apps/authentik-dependencies/application.yaml`
- [ ] PostgreSQL values updated:
  - [ ] Storage class configured
  - [ ] Resource limits adjusted
  - [ ] Passwords referenced from secrets
- [ ] Redis values updated:
  - [ ] Storage class configured
  - [ ] Resource limits adjusted
  - [ ] Password referenced from secret

### Authentik
- [ ] `authentik-app.yaml` copied to `.demo/manifests/apps/authentik/application.yaml`
- [ ] Domain updated (e.g., `auth.your-domain.com`)
- [ ] Secret key referenced from secret
- [ ] Database credentials referenced from secrets
- [ ] Redis credentials referenced from secrets
- [ ] Ingress annotations configured
- [ ] TLS configuration set up

## ✅ Phase 6: Kustomization Updates

- [ ] `.demo/manifests/apps/kustomization.yaml` updated to include:
  - [ ] `external-dns/application.yaml`
  - [ ] `authentik-dependencies/application.yaml`
  - [ ] `authentik-dependencies/secrets/postgres-secret.yaml`
  - [ ] `authentik-dependencies/secrets/redis-secret.yaml`
  - [ ] `authentik/application.yaml`
  - [ ] `authentik/secrets/authentik-secret.yaml`

## ✅ Phase 7: Cluster Deployment

- [ ] Enhanced deploy script executed: `./deploy-enhanced.sh`
- [ ] Cloudflare API token provided during deployment
- [ ] Domain name provided during deployment
- [ ] Cluster deployed successfully
- [ ] Kubeconfig exported
- [ ] Talosconfig exported
- [ ] Cluster nodes are ready
- [ ] ArgoCD installed successfully
- [ ] App-root deployed

## ✅ Phase 8: SOPS Integration

- [ ] Age key stored in cluster as secret
  ```bash
  kubectl get secret sops-age -n argocd
  ```
- [ ] ArgoCD SOPS plugin installed: `./install-argocd-sops.sh`
- [ ] ArgoCD repo-server restarted
- [ ] SOPS decryption verified in ArgoCD logs

## ✅ Phase 9: DNS Configuration

- [ ] Cluster IP obtained
  ```bash
  terraform output -C .demo cluster_endpoint
  ```
- [ ] DNS A record created pointing to cluster IP:
  - [ ] Main domain: `your-domain.com`
  - [ ] Wildcard: `*.your-domain.com`
- [ ] External-DNS pod running
  ```bash
  kubectl get pods -n external-dns
  ```
- [ ] External-DNS logs checked for errors
  ```bash
  kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
  ```

## ✅ Phase 10: Application Deployment

### External-DNS
- [ ] Application synced in ArgoCD
- [ ] Pod running successfully
- [ ] Logs show no errors
- [ ] TXT records visible in Cloudflare

### PostgreSQL
- [ ] Application synced in ArgoCD
- [ ] StatefulSet running
- [ ] PVC created successfully
- [ ] Database accessible from within cluster

### Redis
- [ ] Application synced in ArgoCD
- [ ] Deployment running
- [ ] PVC created successfully
- [ ] Redis accessible from within cluster

### Authentik
- [ ] Application synced in ArgoCD
- [ ] Server deployment running
- [ ] Worker deployment running
- [ ] Ingress created
- [ ] DNS record created by external-dns
- [ ] Application accessible via browser

## ✅ Phase 11: Authentik Configuration

- [ ] Accessed Authentik at `https://auth.your-domain.com`
- [ ] Initial bootstrap token retrieved
  ```bash
  kubectl logs -n authentik -l app.kubernetes.io/name=authentik-server | grep "Bootstrap"
  ```
- [ ] Admin account created
- [ ] Admin password changed from default
- [ ] Email configuration completed (optional)
- [ ] SMTP tested (optional)

## ✅ Phase 12: Testing

- [ ] DNS resolution working
  ```bash
  nslookup auth.your-domain.com
  ```
- [ ] HTTPS working (certificate valid)
- [ ] Authentik login working
- [ ] Authentik admin interface accessible
- [ ] External-DNS creating/deleting records correctly
- [ ] ArgoCD auto-sync working
- [ ] Secret decryption working

## ✅ Phase 13: Documentation

- [ ] Internal documentation created for team
- [ ] Age key backup location documented
- [ ] Recovery procedures documented
- [ ] Access credentials documented (securely)
- [ ] Architecture diagram created (optional)

## ✅ Phase 14: Security Hardening

- [ ] Firewall rules reviewed
- [ ] ArgoCD admin password changed
- [ ] RBAC configured in ArgoCD
- [ ] Network policies created (optional)
- [ ] TLS certificates configured for all services
- [ ] Security scanning configured (optional)

## ✅ Phase 15: Monitoring Setup (Optional)

- [ ] Prometheus operator installed
- [ ] Grafana installed
- [ ] ServiceMonitors enabled
- [ ] Dashboards imported
- [ ] Alerts configured

## ✅ Phase 16: Backup Strategy

- [ ] Database backup strategy defined
- [ ] Velero installed for cluster backups (optional)
- [ ] Backup schedule configured
- [ ] Restore procedure tested

## ✅ Phase 17: First Application Deployment

- [ ] Application manifest created
- [ ] Secrets encrypted with SOPS
- [ ] Added to kustomization.yaml
- [ ] Committed to Git
- [ ] ArgoCD synced application
- [ ] Application accessible
- [ ] DNS record created automatically

## ✅ Phase 18: Team Onboarding

- [ ] Documentation shared with team
- [ ] Age key shared securely with team members
- [ ] Access credentials distributed
- [ ] Training session conducted (if needed)
- [ ] First team member successfully deployed change

## 📊 Progress Tracking

**Phase Completion:**
- Phase 1-5 (Setup): ___/18 tasks
- Phase 6-10 (Deployment): ___/26 tasks  
- Phase 11-14 (Configuration): ___/19 tasks
- Phase 15-18 (Advanced): ___/14 tasks

**Total Progress: ___/77 tasks (____%)**

## 🎯 Success Criteria

Your setup is complete when:
- [ ] All core phases (1-14) are completed
- [ ] You can deploy a new application by committing to Git
- [ ] DNS records are created automatically
- [ ] Secrets are encrypted in Git
- [ ] Authentik is accessible and configured
- [ ] Team members can access and use the system
- [ ] Recovery procedures are documented and tested

## 📝 Notes

Use this section to track issues, decisions, or important information:

```
Date: ___________
Notes:
- 
- 
- 

Issues encountered:
- 
- 

Customizations made:
- 
- 
```

## 🔄 Maintenance Checklist (Weekly)

- [ ] Check ArgoCD sync status
- [ ] Review external-dns logs
- [ ] Check database backups
- [ ] Review cluster resource usage
- [ ] Check for application updates
- [ ] Review security alerts

## 🚨 Troubleshooting Reference

If stuck, refer to:
1. `QUICK-REFERENCE.md` → Troubleshooting section
2. Application logs in Kubernetes
3. ArgoCD application status
4. External-DNS logs for DNS issues

**Common Issues:**
- Secrets not decrypting → Check age key in cluster
- DNS not working → Check external-dns logs and Cloudflare token
- Authentik not starting → Check PostgreSQL and Redis status
- ArgoCD not syncing → Check application sync policy and logs

---

**Last Updated:** ___________  
**Completed By:** ___________  
**Reviewed By:** ___________
