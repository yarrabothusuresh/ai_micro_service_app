# Ledger Manager

A synthetic-data demo of React, Spring Cloud Gateway, three Spring Boot services, Excel-backed Drools account selection and PostgreSQL. There is no Eureka server or discovery-client dependency.

## Layout

- `gateway`: public API routes, CORS and Cloud Run invocation authentication.
- `ui-service`: dashboard API; reads Posting Service APIs rather than its database.
- `rules-service`: compiles `src/main/resources/rules/account-rules.drl.xlsx` at startup and evaluates a new rules session for each request.
- `posting-service`: validates postings, requests account selection, owns PostgreSQL tables and saves the rule audit. Flyway manages the schema.
- `contracts`: small shared API records and HTTP helpers; no shared database entities.
- `frontend`: React and Vite posting form and dashboard.

## Local development

Requirements: Java 21, Maven 3.9+, a current supported Node.js version and Docker with a working Linux engine. The current development machine has Java 21, Maven 3.9.9, Node 24 and Docker Desktop.

Start Docker Desktop, then run the application from PowerShell:

```powershell
cd C:\dev\ai_micro_service_app
.\start.ps1
```

This selects Java 21, builds the Java applications, installs frontend dependencies when the lock file changes, builds React, starts PostgreSQL and all five application processes, waits for their health checks, checks the dashboard API through Gateway and opens the UI. No Neon, GCP or GitHub credentials are needed to run locally. Background helpers use hidden windows. Logs and process identities are stored in the ignored `.local` directory. Startup temporarily supplies local-only environment settings to child processes, then restores the calling shell's environment.

Open `http://127.0.0.1:5173`. Gateway is `http://127.0.0.1:8080`; it forwards to UI API on 8081 and Posting Service on 8083. Posting Service calls Drools on 8082. The Java servers and Vite bind to loopback. PostgreSQL uses port 15432 because another local database already occupies 5432.

Useful commands:

```powershell
.\status.ps1                  # Check application health and the database container
.\stop.ps1                    # Stop this application's recorded processes and database
.\start.ps1 -SkipBuild        # Faster startup after a successful build with unchanged sources
.\start.ps1 -Verify           # Run all backend tests before starting
.\start.ps1 -NoBrowser        # Start without opening a browser
.\scripts\smoke-test.ps1      # Save one synthetic posting and verify its retry and dashboard
```

Running `start.ps1` again while all recorded application processes are healthy reports that the application is already running. It does not create duplicate processes. A conflicting, unrecorded process is not stopped. `stop.ps1` checks executable, entrypoint and process start time before stopping a recorded PID. The database's named volume retains records across stops and restarts. `stop.ps1 -KeepDatabase` leaves the demo database running.

To choose a JDK explicitly, pass `-JavaHome 'C:\path\to\jdk-21'`. Optional local database settings are in `.env.example`; copy it to the ignored `.env` before the first database initialization if you want different local credentials. Changing credentials in `.env` does not change credentials already stored in an existing database volume.

Build and test without starting the application:

```powershell
.\scripts\verify-local.ps1
```

Posting integration tests start a disposable PostgreSQL container and require Docker access. They do not use or modify the application database or Neon.

## Alternative: containerized Java services

After stopping the host-run application, you can instead run the Java services in Docker. This uses Docker service names for internal DNS:

```powershell
docker compose build
docker compose up -d
cd frontend
npm ci
npm run dev
```

Open `http://127.0.0.1:5173`. In this mode Vite proxies `/api` to Gateway. Compose destinations use Docker service names. Stop this containerized mode with `docker compose stop`; stop its foreground React process with Ctrl+C.

Container start order is not service readiness. Wait for the services' `/actuator/health` endpoints to report healthy before running:

```powershell
.\scripts\smoke-test.ps1
```

Stop containers using `docker compose stop`. The named PostgreSQL volume retains saved data. Do not remove the volume unless you intend to discard the local demo records.

## API

| Method | Gateway path | Purpose |
| --- | --- | --- |
| GET | `/api/ui/dashboard` | Count, totals grouped by currency and the latest 50 postings |
| POST | `/api/postings` | Create a posting; requires a UUID `Idempotency-Key` header |
| GET | `/api/postings` | Latest 50 postings |
| GET | `/api/postings/{id}` | One saved posting and its decision audit |

Example synthetic request:

```json
{"reference":"DEMO-001","amount":"123.45","currency":"INR","transactionType":"SALE","narration":"Sample posting"}
```

Supported transaction types are SALE, PURCHASE and REFUND. Supported currencies are INR, USD and EUR. Sample account identifiers are DEMO-4001, DEMO-5001 and DEMO-4002. These identifiers are illustrative and are not production accounting rules.

Reusing a key with the same normalized payload returns the saved result. Reusing it with different fields returns HTTP 409. PostgreSQL enforces unique keys even during concurrent requests. Network calls to Drools occur before the short database transaction. Missing, ambiguous or incomplete account decisions do not save a completed posting.

## Excel rules

Edit the decision table with Excel or another compatible spreadsheet editor while preserving Drools metadata and template rows. Rebuild and deploy the rules-service image after changing it. Its audit version derives from the packaged workbook's SHA-256 hash. Do not edit a deployed container's filesystem to change rules: such edits are ephemeral and would make replicas inconsistent.

## Cloud deployment

The complete procedure and resource list are in [docs/PUBLISHING.md](docs/PUBLISHING.md). Entry points:

```powershell
.\publish.ps1 -Plan            # Review resources and deployment order
.\publish.ps1 -Stage Prepare   # Enable APIs and provision scoped infrastructure
.\configure-cloud.ps1          # Enter Neon settings; hidden password goes to Secret Manager
.\publish.ps1                  # Build, deploy, configure routes and run the cloud smoke test
```

The backend is deployed to GCP project `ledgermanager`, region `us-east4`. Its public API is [Ledger Manager Gateway](https://ledger-gateway-ouadcuheya-uk.a.run.app/); the root returns API information. [Dashboard JSON](https://ledger-gateway-ouadcuheya-uk.a.run.app/api/ui/dashboard) exercises Gateway, UI Service, Posting Service and Neon. The three backend services require platform authentication. Google manages the stable service DNS names; no Eureka is used.

Use `--project=ledgermanager` explicitly; the project number is `434796230124`. Scripts do not change another project's CLI default. Backend settings and deployment records in `.local` contain URLs and secret references, not the database password.

Use one Cloud Run service for each Java application. All listen on Cloud Run's `PORT` environment variable. Use the assigned stable service HTTPS URLs for `RULES_SERVICE_URL`, `POSTING_SERVICE_URL` and `UI_SERVICE_URL`. Backend services require Cloud Run IAM authentication; enable `CLOUD_AUTH_ENABLED=true` in their callers and grant only the relevant service accounts invocation access. Gateway adds `X-Serverless-Authorization` separately from an end-user Authorization header.

Configure Posting Service with `DATABASE_URL` (pooled PostgreSQL JDBC with certificate verification), `DATABASE_MIGRATION_URL` (the direct endpoint), `DATABASE_USERNAME` and a pinned `DATABASE_PASSWORD` Secret Manager version. Flyway 11.20.3 supports the Neon PostgreSQL 18 database. Do not expose the password to React or commit it to Git.

React's production build uses `VITE_API_BASE_URL` for the Gateway HTTPS URL and `VITE_BASE_PATH=/ai_micro_service_app/` for GitHub Pages project hosting. Set Gateway `FRONTEND_ORIGINS` to the origin `https://yarrabothusuresh.github.io` (no repository path).

After committing the reviewed source to `main`, run `publish-frontend.ps1` to push to the approved public repository and deploy React through GitHub Pages. It uses an existing GitHub CLI or cached Git login, checks administrator access, configures the API URL and watches the workflow. Run `verify-cloud.ps1` to check the backend without creating data, or add `-SmokeTest` to save and verify one sample posting.

Deploy and verify in this order: database, rules, posting, UI API, Gateway, React. Cloud URLs are infrastructure-managed stable hostnames; no custom domain purchase or private DNS server is required for this demo. Protecting invocation with IAM does not by itself make an endpoint network-private.

Use synthetic data only. The public demonstration UI does not yet include a user login or production access policy. Review authentication, authorization, abuse limits and monitoring before accepting real users or data.

The free allowances are usage-limited. Request-based billing, minimum instances zero and a low maximum instance count reduce costs but do not impose a hard spending cap.

## Implementation status

The backend suite covers five Excel/Drools tests, six PostgreSQL integration tests and six real-HTTP Gateway tests including CORS and the API root. PostgreSQL integration tests now target version 18 to match Neon. The local launcher previously passed health, posting, retry, repeat-start and persistence checks; process ownership guards rejected mismatched start times and entrypoints. Docker Desktop must be running for local tests and startup.

All four Java services are deployed. The cloud workflow saved one synthetic posting with its Excel-selected account and rule version, read it back, returned the same record on retry, and loaded the dashboard. Anonymous access to each backend returned 403, while Gateway and the configured frontend CORS preflight succeeded. The PostgreSQL 18-compatible Flyway image was redeployed at the same Posting Service URL. Browser visual verification and the alternative Docker-based Java runtime remain separate checks. See `IMPLEMENTATION_PLAN.md` for the ordered work.
"# ai_micro_service_app" 
