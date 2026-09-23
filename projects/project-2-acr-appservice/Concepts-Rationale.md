Concepts & Rationale — Project 2 (ACR + App Service)

The "why" behind this project — for interview questions like "walk me through your deployment strategy and why you designed it that way" or "what did you learn from this project."

Why this project exists (the business problem)

Starting premise: a small engineering team wants to containerize an internal app so it runs identically on every developer's laptop and in production, and wants every push to main to automatically build, test, and deploy it.

Two separate problems are being solved:

1. The "works on my machine" problem. Without containers, an app can work on a developer's laptop but break in production because of different OS versions, missing dependencies, or different runtime versions. Docker packages the app and everything it needs (Python, libraries, system packages) into one portable image that runs identically everywhere — laptop, teammate's laptop, Azure, anywhere.

2. Manual deployment is slow and error-prone. Without CI/CD, someone manually builds the image, manually pushes it, manually logs into a server and restarts it. This is slow and inconsistent — wrong image tag, skipped tests, deployed at a bad time. Automating this means: push code → everything happens automatically, the same way, every time.

What the project demonstrates (core concepts)
1. Infrastructure as Code (Terraform)

Instead of clicking through the Azure Portal to create resources — not repeatable, not reviewable, not version-controlled — infrastructure is described in code that lives in Git. Benefits:

Every infra change goes through the same review process as application code
The exact same environment can be recreated in a different region or for a second team by running the same code
Terraform Cloud adds: remote state (not sitting on a laptop where it can be lost or corrupted), locking (two people can't apply simultaneously and corrupt state), and a plan-review-apply workflow (nothing changes in Azure without a human explicitly approving it)
2. OIDC over static credentials

Instead of generating a service principal password and pasting it into GitHub secrets (which then sits there indefinitely, often unrotated for years), OIDC means Azure AD issues a short-lived token each time a specific, verified pipeline run asks for one. If a token ever leaked, it's already expired within minutes — there's no long-lived secret to steal in the first place.

3. Least privilege via separate identities

Two separate Azure AD app registrations were used — one for Terraform, one for GitHub Actions — each scoped to only what it needs:

Terraform needed to create resources and grant permissions to other identities, so it got Contributor + User Access Administrator
GitHub Actions only needed to push images and update an existing App Service, so it got Contributor scoped to just the resource group

If GitHub Actions' credentials were ever compromised, the blast radius is one resource group — not the whole subscription.

4. Managed Identity for service-to-service auth

Instead of the App Service holding a username/password to log into ACR (yet another secret to manage and rotate), the App Service has an Azure-managed identity, and that identity was granted the AcrPull role directly. No credentials exist anywhere for this connection — Azure handles the authentication internally.

Deployment slots, smoke testing, and the swap — the core deployment pattern
The problem this solves

Imagine deploying directly to production with no slots:

GitHub Actions builds the new image
It tells App Service "use this new image now"
App Service pulls the image and restarts
If the new image is broken — crashes on startup, has a bug, missing a dependency — production is now down, and real users hit errors until someone notices and manually rolls back.

That gap between "deployed" and "someone notices it's broken" could be minutes. For a real business, that's real money lost and real user trust damaged.

How deployment slots fix this

A deployment slot is a completely separate, fully running copy of the App Service, with its own URL (myapp-prod-app-staging.azurewebsites.net), sharing the same underlying App Service resource. Like having two identical apartments — one can be renovated while people are still comfortably living in the other.

Why the smoke test matters — concrete example

What actually happens in the pipeline, step by step, and why each step exists:

1. Build image
2. Scan image (Trivy)
3. Push image to ACR
4. Deploy new image → STAGING slot only (production untouched, still running old version)
5. Restart staging slot
6. Smoke test: curl staging-slot-url/health, retry up to 10 times over ~100 seconds
7. IF smoke test passes → swap staging into production
8. IF smoke test fails → pipeline stops here, production was NEVER touched

Concrete example of what the smoke test catches: suppose new code has a bug — a missing dependency, or the health check route was accidentally changed from /health to /healthz without updating the Azure config.

Without smoke testing: the broken image deploys straight to production. Every real user immediately hits errors. Someone has to notice, investigate, and manually roll back — potentially 10–30 minutes of real outage.
With smoke testing: the broken image deploys to the staging slot only. The smoke test hits /health on staging, gets a non-200 response or times out for 100 seconds, and the pipeline fails right there. Production users never see any disruption — they're still using the old, working version. The failure is immediately visible in GitHub Actions, and debugging happens with zero user-facing impact.

This is exactly what happened during this project's build-out — the ImagePullUnauthorizedFailure and the port-mismatch issue were both caught by the smoke test failing. Because deployment slots were in place, production was never actually broken at any point during that troubleshooting. That's the pattern working as designed, demonstrated in practice, not just in theory.

Why the swap, specifically (not just "copy the new version over")

The "swap" is not a redeploy — it's an instant traffic redirect. Azure swaps which slot answers to which URL. This is different from stopping production and restarting it with new code (which causes downtime while it restarts).

Before swap:
  production URL  →  [old code, Slot A]
  staging URL      →  [new code, Slot B]

After swap:
  production URL  →  [new code, Slot B]
  staging URL      →  [old code, Slot A]

Both apps were already running and warmed up before the swap, so there's no cold-start delay and no downtime. It's a routing change, not a restart — this is called near-zero-downtime deployment.

Bonus — instant rollback. If a problem is discovered minutes after the swap (something the smoke test didn't catch, like a subtle business-logic bug), swapping back is immediate:

bash
az webapp deployment slot swap --slot production --target-slot staging

Instant, because the old code never went anywhere — it's just sitting in the other slot.

Why this beats a plain rolling deploy for this use case

An alternative is a rolling deploy (common with Kubernetes) — replacing instances one at a time while the load balancer sends some traffic to old instances and some to new ones during the transition. That works, but:

Two versions serve traffic simultaneously for a period — fine for stateless apps, but can cause subtle bugs if versions aren't compatible with each other's data/API contracts
If the new version is broken, some fraction of real users already hit it before the rollout is noticed and stopped

Slot swap avoids both — it's binary. Either 100% of traffic is on the fully-verified new version, or 0%. No partial exposure.

The full mental model, end to end
Developer pushes code
        │
        ▼
GitHub Actions builds + scans the image
        │
        ▼
Image pushed to ACR (a private, versioned image store)
        │
        ▼
New image deployed to STAGING slot only
   (production keeps serving old version, unaffected)
        │
        ▼
Smoke test hits staging's /health endpoint
        │
   ┌────┴────┐
   │         │
 FAILS     PASSES
   │         │
   ▼         ▼
Pipeline   Swap staging ↔ production
 stops     (instant, no downtime)
 here            │
                 ▼
         Final health check confirms
         production is genuinely healthy

The core lesson across the whole project: every layer exists to catch failure as early and as cheaply as possible, before it reaches a real user.

Trivy catches vulnerable dependencies before they ship
The staging slot catches broken deployments before they're customer-facing
The smoke test is the automated judge deciding whether a deployment is trustworthy enough to become production
The swap makes the actual cutover instant and trivially reversible
Likely interview framing for this material

"Walk me through your deployment strategy and why." Start with the failure mode being prevented (broken deploy reaching real users), then walk the pipeline stage by stage, ending on the swap and rollback story.

"What did you learn from this project?" Good answer shape: one infra lesson (state drift is real and needs state rm/import, not blind re-applies), one security lesson (OIDC + least privilege beats static secrets), one deployment lesson (slots + smoke tests turn "deploy and hope" into "deploy and verify").

"How would you improve this further?" Natural next steps to mention: automated rollback triggered by Application Insights alerting on error rate post-swap, canary-style partial traffic shifting instead of instant 100% swap for higher-risk changes, and promoting the Trivy scan to also gate on image signing/provenance.