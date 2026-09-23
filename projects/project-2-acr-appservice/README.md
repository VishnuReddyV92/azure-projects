# Architecture

Dev pushes to main
       │
       ├── projects/project-2-acr-appservice/terraform/**  →  Terraform Cloud (VCS-driven)
       │        │
       │        ├── Plan runs automatically
       │        ├── Manual "Confirm & Apply" in TFC UI
       │        └── Provisions: Resource Group, ACR, App Service Plan,
       │            App Service + staging slot, App Insights, RBAC role assignments
       │
       └── projects/project-2-acr-appservice/app/**  →  GitHub Actions
                │
                ├── az login (OIDC, no stored secrets)
                ├── docker build
                ├── Trivy vulnerability scan (fails on fixable CRITICAL/HIGH CVEs)
                ├── docker push → ACR
                ├── Deploy image to staging slot
                ├── Restart staging slot
                ├── Smoke test staging (/health, retries for ~100s)
                ├── Slot swap: staging → production
                └── Final health check on production URL
Both pipelines authenticate to Azure via OIDC federated credentials — no client secrets or passwords stored anywhere in TFC, GitHub, or the repo.

# Repository structure
azure-projects/                              (repo root — .git lives here)
├── .github/
│   └── workflows/
│       └── project-2-build-deploy.yml        GitHub Actions: build/scan/push/deploy
├── projects/
│   └── project-2-acr-appservice/
│       ├── app/
│       │   ├── src/
│       │   │   ├── app.py                    Flask app (/ and /health routes)
│       │   │   └── requirements.txt
│       │   ├── Dockerfile
│       │   └── .dockerignore
│       └── terraform/
│           ├── backend.tf                    TFC cloud backend config
│           ├── providers.tf                  azurerm ~> 4.0
│           ├── variables.tf
│           ├── main.tf                       Resource group
│           ├── acr.tf                        Container registry
│           ├── app_service.tf                Service plan, web app, staging slot
│           ├── identity.tf                   AcrPull role assignments
│           ├── monitoring.tf                 Application Insights
│           └── outputs.tf
└── README.md

# Tool stack

Docker · Azure Container Registry (Basic SKU) · Azure App Service (Linux, S1 Standard, with deployment slots) · Terraform · Terraform Cloud (VCS-driven workspace) · GitHub Actions · Azure AD Managed Identity · Trivy (image vulnerability scanning) · Application Insights

# Setup steps (in order)

# 1. Azure AD app registration for Terraform Cloud (OIDC)
Created app registration tfc-oidc-project2 in Azure Portal
Added two federated credentials (issuer https://app.terraform.io), one for run_phase:plan and one for run_phase:apply, subject scoped to the TFC org/workspace name
Assigned Contributor on the subscription
Assigned User Access Administrator on the resource group (required — Contributor alone cannot create RBAC role assignments; this is a deliberate Azure security boundary)
# 2. Terraform Cloud workspace (VCS-driven)
Created workspace project2-acr-appservice, connected via GitHub App (not classic repo webhook) to azure-projects
Set Terraform working directory: projects/project-2-acr-appservice/terraform
Set VCS branch: main
Set automatic run triggering to "Only trigger runs when files in specified paths change", pattern: projects/project-2-acr-appservice/terraform/**/* (must click "Add pattern" to actually save it — typing alone doesn't persist it)
Set workspace environment variables: ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, ARM_USE_OIDC=true, TFC_AZURE_PROVIDER_AUTH=true, TFC_AZURE_RUN_CLIENT_ID
Left Auto-apply disabled — every apply requires manual "Confirm & Apply" in the TFC UI
# 3. Terraform infrastructure

Provisioned via terraform/*.tf:

Resource Group
ACR (Basic SKU, admin account disabled, globally-unique name with suffix)
App Service Plan (S1 Standard — required; Basic tier does not support deployment slots)
Linux Web App + staging deployment slot, both with System-Assigned Managed Identity
AcrPull role assignment for both the production and staging slot identities, scoped to the ACR only
Application Insights, connection string wired into app settings
WEBSITES_PORT=8000 app setting (container listens on 8000; App Service defaults to expecting port 80 otherwise)
container_registry_use_managed_identity = true in site_config (tells App Service to pull using its Managed Identity instead of registry username/password)
# 4. Azure AD app registration for GitHub Actions (OIDC)
Created separate app registration github-actions-project2 (kept separate from the TFC identity for least-privilege / blast-radius isolation)
Added federated credential via Portal's built-in "GitHub Actions deploying Azure resources" template, trusting repo:<org>/azure-projects:ref:refs/heads/main
Assigned Contributor, scoped only to the resource group (not the subscription) — sufficient since this identity only ever updates an existing App Service and pushes to an existing ACR
# 5. GitHub repository secrets

AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, ACR_NAME, ACR_LOGIN_SERVER, AZURE_RESOURCE_GROUP, APP_SERVICE_NAME (last four pulled from terraform output)

# 6. Application code

Minimal Flask app (/ and /health routes) containerized with a python:3.12-slim Dockerfile, running as non-root user via gunicorn on port 8000.

# 7. GitHub Actions workflow

.github/workflows/project-2-build-deploy.yml, triggered on push to main scoped to projects/project-2-acr-appservice/app/**. Steps: OIDC login → build → Trivy scan (ignore-unfixed: true, fails only on patchable CRITICAL/HIGH CVEs) → push to ACR → deploy to staging slot → restart → smoke test → slot swap → final production health check.

Problems hit and how they were fixed
Problem	Root cause	Fix
No event triggers defined in 'on'	Workflow YAML file was empty	Rewrote the file with full valid content
TFC never auto-triggered on push	Path-pattern filter was left empty in workspace VCS settings	Entered pattern and clicked "Add pattern" to actually save it
Missing required argument: health_check_eviction_time_in_min	azurerm v4 requires this arg whenever health_check_path is set	Added health_check_eviction_time_in_min = 2 alongside health_check_path
ACR name AlreadyInUse	ACR names are globally unique across all of Azure, not per-subscription	Appended a unique suffix to the name
App Service Plan quota 401 Unauthorized	Subscription had 0 quota for B1 VMs in eastus	Switched region to centralindia
Staging slot 409 Conflict — exceeds slots allowed for Basic SKU	B1 (Basic) tier supports zero deployment slots	Upgraded Service Plan SKU to S1 (Standard)
Role assignment 403 AuthorizationFailed	Contributor role does not include Microsoft.Authorization/roleAssignments/write	Granted TFC's identity User Access Administrator on the resource group
Plan/apply errors: 404 Not Found on resources that appeared to exist	State drift — Terraform state referenced resources no longer present (or not yet consistent) in Azure	Used terraform state rm for genuinely-deleted resources, terraform import to re-adopt resources that did exist but fell out of state
Trivy scan failed the build	44 HIGH-severity CVEs in base Debian image packages, none with an available fix	Added ignore-unfixed: true to the Trivy step — only fail on vulnerabilities that are actually actionable
Deploy succeeded but /health never returned 200	App Service defaulted to expecting traffic on port 80; container listens on 8000	Added WEBSITES_PORT=8000 app setting
ImagePullUnauthorizedFailure in container startup logs	App Service wasn't configured to use its Managed Identity to authenticate the ACR pull	Set container_registry_use_managed_identity = true in site_config
terraform destroy had no visible button in TFC UI	Looked in the wrong place initially	Found under Settings → Destruction and deletion → Queue destroy plan
Local git pull blocked with divergent branches	Local commits and remote commits both modified the same file independently	Set git config pull.rebase false (merge strategy) and resolved via merge commit
Verifying the deployment
bash
curl https://<app-service-name>.azurewebsites.net/health
# {"status": "healthy"}

curl https://<app-service-name>.azurewebsites.net/
# {"message": "Hello from ACR + App Service!", "version": "dev"}
Tearing down
bash
# Via TFC UI (recommended):
# Workspace → Settings → Destruction and deletion → Queue destroy plan → Confirm & Apply

# Or locally:
cd projects/project-2-acr-appservice/terraform
terraform destroy

Verify clean:

bash
az group list -o table
az acr list -o table
az webapp list -o table
Interview questions and answers

Why avoid the latest tag in production image deployments? It isn't immutable — you can't tell which code is actually running, can't reliably roll back to a specific version, and redeploying the same tag doesn't guarantee App Service pulls new bits. A Git-SHA tag makes every deployment traceable and reproducible.

How does Managed Identity remove the need for registry credentials? Azure AD issues the App Service an identity token; the AcrPull role assignment on that identity lets ACR authenticate the pull without any stored username/password.

What's the difference between a deployment slot swap and a rolling deploy? A slot swap does a full cutover between two warmed-up environments (near-instant, trivial rollback by swapping back); a rolling deploy incrementally replaces instances behind a load balancer, so old and new versions briefly serve traffic simultaneously.

How would you scan container images for vulnerabilities in a pipeline? Add a scanner step (Trivy, Grype, or ACR's own Defender for Cloud integration) between build and push, configured to fail the workflow on critical/high CVEs that have an available fix — so vulnerable, patchable images never reach the registry.

Why split Terraform (TFC) and app deploy (GitHub Actions) into two separate pipelines? Different blast radii and cadences — infra changes are rare and need review/approval; app deploys happen frequently and should be fast. Separating them means a bad app deploy can't accidentally touch infra state, and vice versa.

Why OIDC instead of a service principal secret? No credential to leak, rotate, or expire. The identity provider issues a short-lived token per run, scoped narrowly by the federated credential's subject claim.

Why two separate app registrations (TFC and GitHub Actions)? Least privilege — TFC needs subscription/RG-level Contributor plus RBAC-management rights to create resources and role assignments; GitHub Actions only needs to push to ACR and update the App Service container, so it's scoped to the resource group only.

Why does Contributor alone fail when creating role assignments? Azure deliberately separates resource management from access management — Contributor can create/modify resources but cannot grant permissions to others; that requires Microsoft.Authorization/roleAssignments/write, provided by roles like User Access Administrator or Owner.