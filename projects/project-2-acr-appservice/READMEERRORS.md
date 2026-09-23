Issues Faced — Project 2 (ACR + App Service) — Interview Notes

Real production-style issues hit while provisioning Azure infra via Terraform and deploying a Docker image to ACR/App Service, with root cause and fix for each. Useful for "tell me about a challenge you faced" style interview questions.

Infrastructure provisioning issues (Terraform / Azure)
1. ACR name conflict — AlreadyInUse

Symptom: Error: creating Registry ... AlreadyInUse: The registry DNS name myappprodacr.azurecr.io is already in use

Root cause: ACR names must be globally unique across all of Azure, not just within my subscription — someone else already owned that name.

Fix: Appended a unique suffix to the ACR name (e.g. myappprodacrvvr01).

How I'd explain it in an interview: "ACR registry names live in a global DNS namespace (*.azurecr.io), so naming collisions across unrelated subscriptions are a real possibility — I now always parameterize ACR names with an org/environment-specific suffix to avoid this."

2. App Service Plan quota error — 401 Unauthorized

Symptom: Current Limit (B1 VMs): 0, Current Usage: 0, Amount required for this deployment (B1 VMs): 1 — plan creation rejected.

Root cause: My subscription (trial/sandbox tier) had zero compute quota allocated for B1 VMs specifically in the eastus region. Quota is allocated per-region, not subscription-wide.

Fix: Switched the deployment region to centralindia, which had available quota. (Alternative long-term fix: request a quota increase via Portal → Quotas.)

How I'd explain it in an interview: "Trial and sandbox subscriptions often have region-specific compute quota limits — I diagnosed it by reading the exact quota numbers in the error payload, and resolved it by picking a region with available capacity rather than blindly retrying."

3. Deployment slot creation failed — 409 Conflict, exceeds Basic SKU slot limit

Symptom: Cannot complete the operation because the site will exceed the number of slots allowed for the 'Basic' SKU.

Root cause: Azure App Service Basic (B1) tier supports zero additional deployment slots — slots require Standard (S1) tier or higher. This is a hard platform limitation, not a config error.

Fix: Upgraded the App Service Plan SKU from B1 to S1.

How I'd explain it in an interview: "This is a good example of a platform-tier limitation rather than a bug — I had to know that deployment slots are a Standard-tier-and-above feature, which directly affects cost/architecture decisions when someone asks for blue-green style deployments."

4. Role assignment failed — 403 AuthorizationFailed

Symptom: does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'

Root cause: The Terraform Cloud service principal had Contributor role, which lets it create/modify resources — but Azure deliberately separates resource management from access/identity management. Granting RBAC roles to other identities (like giving the App Service's Managed Identity AcrPull access) requires a role like User Access Administrator, which Contributor does not include.

Fix: Granted the Terraform identity User Access Administrator, scoped to just the one resource group (not subscription-wide, to keep blast radius contained).

How I'd explain it in an interview: "This is a core Azure RBAC concept — Contributor and Owner are not the same thing, and the separation exists specifically so that a compromised or over-eager automation identity can't grant itself or others broader access. I scoped the extra permission down to a single resource group rather than the subscription, following least-privilege."

5. State drift — Terraform thought resources existed, but Azure returned 404

Symptom: Error: retrieving Billing Features for Component ... 404 Not Found ... ParentResourceNotFound and similarly for the App Service itself, even though terraform state list showed them as tracked.

Root cause: Terraform's state file had stale records for resources that had been deleted (or, in one case later, resources that genuinely still existed but the read had a transient consistency lag) — a classic state drift scenario where reality and state diverge.

Fix: Used terraform state rm <resource> to make Terraform forget about a resource that was genuinely gone (so it would recreate cleanly on next apply), and terraform import <resource> <azure_resource_id> to re-adopt a resource that did still exist in Azure but had fallen out of state — without this it would have tried to create a duplicate and hit a naming conflict.

How I'd explain it in an interview: "State drift is one of the most common real-world Terraform issues — it happens when infrastructure changes outside of Terraform's knowledge, whether through manual deletion, a partially-failed apply, or API eventual consistency. The key is knowing the difference between state rm (stop tracking something) and import (start tracking an existing resource) rather than just re-running apply and hoping."

Docker image / ACR push / App Service deployment issues
6. Trivy vulnerability scan failed the build

Symptom: Pipeline failed at the scan step with 44 HIGH-severity CVEs found in the base image's OS packages (util-linux, ncurses, systemd, etc.), most showing status "affected" with no fixed version available.

Root cause: These were vulnerabilities in the base Debian image's system packages that had no patch released yet — not something fixable by updating application dependencies.

Fix: Added ignore-unfixed: true to the Trivy scan step, so the pipeline only fails on vulnerabilities that actually have an available fix — making the gate meaningful and actionable instead of permanently blocking on unpatchable noise.

How I'd explain it in an interview: "A vulnerability gate that blocks on CVEs with no available fix just trains the team to ignore or bypass the scanner. I configured it to fail only on patchable, actionable vulnerabilities — the scan still catches genuinely fixable issues, but doesn't create false urgency for things nobody can act on yet."

7. Deploy succeeded but health checks never passed — wrong port

Symptom: Image pushed to ACR successfully, App Service deployment step succeeded, but the smoke test looped and timed out hitting /health.

Root cause: My Flask app (via gunicorn) listens on port 8000 inside the container, but Azure App Service for Linux containers defaults to expecting traffic on port 80 unless told otherwise — so the platform's routing never reached the app.

Fix: Added the WEBSITES_PORT=8000 app setting so App Service knows which port to route to.

How I'd explain it in an interview: "This is a classic 'deploy succeeded, app didn't' gap — the container was healthy, but App Service's front-end didn't know where to send traffic. Always verify the exposed port matches the platform's routing config for custom containers."

8. Container failed to start — ImagePullUnauthorizedFailure

Symptom: Container startup logs showed Failed to pull image: <acr>.azurecr.io/myapp:<sha>. Image pull failed with forbidden or unauthorized. The site got auto-blocked for repeated cold-start failures.

Root cause: Even though the App Service's Managed Identity had been granted AcrPull on the ACR via Terraform, App Service itself wasn't configured to actually use Managed Identity when authenticating the pull — it was still expecting registry username/password credentials that were never supplied.

Fix: Added container_registry_use_managed_identity = true inside the site_config block for both the production app and the staging slot.

How I'd explain it in an interview: "Granting the RBAC role alone isn't enough — the App Service resource itself needs an explicit setting telling it to authenticate via Managed Identity rather than the legacy admin-credential flow. This is an easy step to miss since the role assignment succeeding gives false confidence that the pull path is fully wired."

General workflow / tooling issues
9. GitHub Actions workflow never triggered — path filter never saved

Symptom: Pushing changes to terraform/** produced no run in Terraform Cloud, despite VCS connection showing "Connected."

Root cause: In the TFC workspace's VCS trigger settings, I had typed a path pattern into the input box but never clicked "Add pattern" — so the field was visually populated but nothing was actually saved to the trigger rule list.

Fix: Clicked "Add pattern" to actually commit the pattern, then confirmed it appeared as a saved entry before saving the page.

How I'd explain it in an interview: "A good reminder that UI state and saved state aren't always the same thing — I now always verify a setting actually persisted (by reloading the page) rather than assuming a filled-in field means it's saved."

10. Empty/broken workflow YAML

Symptom: Error: No event triggers defined in 'on'

Root cause: The workflow file had been pushed with no content — the on: block (and everything else) was missing entirely.

Fix: Rewrote the complete, valid workflow YAML and pushed again.

How I'd explain it in an interview: "Straightforward but worth mentioning — always validate a YAML pipeline file has actual content before assuming a trigger misconfiguration; GitHub's error message here was precise enough to point directly at the cause."