# Publish Ledger Manager to GCP

Target project: `ledgermanager`. Target region: `us-east4`. The Neon database already exists in AWS Ohio. All Java applications run as separate Cloud Run services. Google provides their stable HTTPS hostnames; no Eureka or custom DNS zone is used.

## 1. Review and prepare

Run from `C:\dev\ai_micro_service_app` in PowerShell with an authenticated Google Cloud CLI:

```powershell
.\publish.ps1 -Plan
.\publish.ps1 -Stage Prepare
```

Preparation enables Cloud Run, Cloud Build, Artifact Registry, Secret Manager, IAM and Storage APIs. It creates the `ledger-demo` Docker repository, a private source-upload bucket and service accounts named `ledger-build`, `ledger-rules`, `ledger-posting`, `ledger-ui` and `ledger-gateway`. Build permissions are scoped to source-bucket reads, image-repository writes, log writes and API usage. Runtime accounts receive only the service invocation and secret access needed below. Scripts always pass the project explicitly and do not change your CLI's global project.

Cloud Run is usage billed beyond its free allowances. Each application has minimum instances zero and maximum instances one. Rules gets 1 GiB RAM; the other services get 512 MiB. Builds, source/image storage and network transfer can have separate charges. These settings are not a hard spending cap.

## 2. Configure Neon without putting its password in chat

Open Neon Connect and obtain the hostname, database name, username and existing database password. Then run:

```powershell
.\configure-cloud.ps1
```

The first three fields are ordinary prompts. The password prompt is hidden. The script uploads the exact password to Secret Manager in `ledgermanager` over HTTPS, saves only its numeric secret-version reference, and does not write the password to a local file. Local non-secret connection settings are saved to the ignored `.local/cloud-settings.json`.

If you have already placed the password in Secret Manager, use a pinned numeric version and avoid the password prompt:

```powershell
.\configure-cloud.ps1 `
  -DatabaseHost '<Neon hostname>' `
  -DatabaseName '<database>' `
  -DatabaseUsername '<username>' `
  -PasswordSecret 'ledger-neon-password' `
  -ExistingSecretVersion '1'
```

The JDBC URL enables `sslmode=verify-full` and Java's standard trusted certificate authorities. Application queries use the supplied endpoint, including its pooler when selected. Flyway uses the corresponding direct endpoint for schema migrations. Enter a real Neon hostname ending in `.neon.tech`; do not paste a password-bearing connection URI. The cloud profile requires database settings and destination URLs instead of falling back to localhost or demo credentials.

## 3. Publish the backend server

```powershell
.\publish.ps1
```

The script builds container images from the sanitized backend source and deploys in this order:

| Cloud Run service | Destination configuration | Invocation access |
| --- | --- | --- |
| `ledger-rules` | Packaged Excel rules | Posting account only |
| `ledger-posting` | Rules HTTPS URL; Neon JDBC URL and password secret | UI API and Gateway accounts |
| `ledger-ui` | Posting HTTPS URL | Gateway account only |
| `ledger-gateway` | UI and Posting HTTPS URLs; frontend origin | Public synthetic-data demo |

All services are initially deployed with authenticated invocation. Only after backend routes and caller permissions exist does the script grant public invocation to Gateway. Existing unrelated IAM members are not removed. Platform invocation authentication is separate from end-user authentication; the demo currently has no user-login feature.

Cloud Run startup probes check `/actuator/health/liveness`. `SPRING_PROFILES_ACTIVE=cloud` selects the required cloud settings. Runtime service identities obtain short-lived Google ID tokens; no service-account key files are needed. Only Posting's account receives read access to the database password secret, pinned to its configured version.

The script prints the Gateway URL and runs a smoke test that saves one synthetic SALE posting, retries it with the same idempotency key, reads its saved rule audit and loads the dashboard. It records non-secret service/image URLs in `.local/cloud-deployment.json`. Gateway `/` identifies the API and lists its API paths. `/api/ui/dashboard` and `/api/postings` are the business routes; `/` on Posting Service is not a React page.

To publish just the protected rules service before supplying database settings:

```powershell
.\publish.ps1 -Stage Rules
```

This does not publish a usable posting application by itself.

After this protected rules deployment succeeds, use `publish.ps1 -Continue` to retain its verified ready image and URL while publishing the remaining services. Publishing without `-Continue` rebuilds every service from current source.

## 4. Publish the React UI

The approved public repository is `yarrabothusuresh/ai_micro_service_app`. Commit the reviewed source on `main`, then run:

```powershell
.\publish-frontend.ps1
```

This checks the repository and administrator identity, performs an ordinary Git push, sets the non-secret Actions variable `GATEWAY_URL`, enables Pages with GitHub Actions, and dispatches and watches the React deployment. It uses GitHub CLI sign-in or Git's existing cached sign-in for `yarrabothusuresh`. A reused OAuth token stays in process memory and is cleared afterwards; it is never printed or written to a file. If neither login exists, complete `gh auth login --hostname github.com --web` yourself.

The workflow builds with base path `/ai_micro_service_app/`. The intended frontend address is `https://yarrabothusuresh.github.io/ai_micro_service_app/`. Gateway allows its origin `https://yarrabothusuresh.github.io`; origin configuration must not include a repository path.

## Source and credential handling

`.gcloudignore` permits only the Java modules, root Maven file, Dockerfile and build specification. It excludes local runtime files, environment files, build outputs and generated inspection artifacts. `.dockerignore` applies another exclusion layer. Never place a password or token in a Docker build argument, a frontend `VITE_` variable, a Git commit, or a command argument.

## Verification before sharing

```powershell
.\verify-cloud.ps1             # Check Gateway, dashboard, backend access and CORS without saving data
.\verify-cloud.ps1 -SmokeTest  # Also save and verify one synthetic posting
```

Confirm the public Gateway root responds, the dashboard loads, an example posting selects the expected account, retrying does not duplicate it, browser CORS allows the actual frontend, and unauthenticated requests to the three backend service URLs are denied. Verify the saved decision's rule version is present. Review logs and billing after the test. Keep the first deployment limited to synthetic data.
