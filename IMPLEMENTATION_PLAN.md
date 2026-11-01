# Account Posting Demo — implementation plan

## Agreed outcome

Build a new demonstration application locally, verify the complete workflow, then deploy it. Keep Spring Cloud Gateway and use configured HTTP/HTTPS destinations without Eureka.

The initial UI has a posting form with reference, amount, currency, transaction type and narration, plus a dashboard showing saved postings and totals. Use synthetic data and sample account-selection rules. This is a posting-record demo; it is not a complete double-entry accounting ledger.

## Deployment choices

| Component | Local | Cloud target |
| --- | --- | --- |
| React + Vite frontend | localhost:5173 | GitHub Pages if the sample repository is public; otherwise Cloud Run |
| Spring Cloud Gateway | localhost:8080 | Cloud Run |
| UI / dashboard API | localhost:8081 | Cloud Run |
| Drools account decision API | localhost:8082 | Cloud Run |
| Posting API | localhost:8083 | Cloud Run |
| PostgreSQL | Docker, localhost:15432 | Neon PostgreSQL |

Use Java 21 and a compatible Spring Boot / Spring Cloud release combination. Select and pin dependency versions during scaffolding. Keep all applications in a single repository with separate service directories and Dockerfiles.

In Docker Compose, containers use service names such as `posting-service` and `rules-service`, not `localhost`, to call each other. Host-run applications use localhost and the published ports. In Cloud Run, configure destinations with the stable service HTTPS URLs. Do not configure `lb://` destinations or introduce a service registry for this design.

## Workflow and boundaries

1. React submits a posting and an idempotency key to Gateway.
2. Gateway forwards `/api/postings/**` to Posting Service.
3. Posting Service validates the request and checks the idempotency key.
4. Posting Service calls Drools with the posting facts.
5. Drools returns one account, the rule identifier and the immutable rule version.
6. Posting Service atomically saves the posting and its decision audit to PostgreSQL.
7. Gateway forwards `/api/ui/**` to UI Service. UI Service reads dashboard data through Posting Service APIs.

Posting Service owns the posting database tables. Drools never saves postings, and UI Service does not query posting tables directly.

## Demonstration rules

| Transaction type | Sample account code | Sample account label |
| --- | --- | --- |
| SALE | DEMO-4001 | Demo sales |
| PURCHASE | DEMO-5001 | Demo purchases |
| REFUND | DEMO-4002 | Demo refunds |

These are sample identifiers, not accounting advice or production account mappings. Store the sample Excel decision table in the rules-service source and package it in the application image. Compile and validate it at startup. Evaluate against a fresh request-specific rules session and dispose the session after use. Return an explicit error for no match or multiple matches.

## Ordered implementation steps

| Step | Work | Completion evidence |
| --- | --- | --- |
| 1 | Confirm prerequisites, demo fields and cloud target | Java 21, Maven, Node/npm, Docker, GitHub and GCP readiness recorded; destination project chosen |
| 2 | Create the repository layout, local configuration and PostgreSQL Compose service | Documented startup commands; PostgreSQL accepts a connection |
| 3 | Implement Posting Service and schema migrations | Valid records persist; validation and duplicate handling behave correctly |
| 4 | Implement Excel-backed Drools decisions and integrate Posting Service | SALE, PURCHASE and REFUND select their expected sample accounts; invalid decisions do not save completed postings |
| 5 | Implement UI/dashboard API and local Gateway routing | Gateway serves both API paths without Eureka; dashboard totals are grouped by currency |
| 6 | Build React posting form and dashboard | A user can create a posting and see its account, rule version and saved record; loading and failure states work |
| 7 | Verify the local stack and create container images | Browser workflow succeeds; meaningful service tests pass; persistence survives application restart |
| 8 | Deploy database and Java services, then Gateway and React | Backend stable URLs configured; only permitted service identities can invoke backend Cloud Run services; Gateway CORS permits the frontend origin |
| 9 | Repeat the workflow in the cloud | Create and list a posting; verify rule audit and database persistence; duplicate retry does not create a second row; redeployment preserves the service URL |

Build and verify Gateway locally before deployment. Deploy it after its backend services in the cloud so their destination URLs are known.

## Verification cases

- One successful posting for each transaction type.
- Missing reference, invalid amount, unsupported input and excessive field lengths produce validation errors.
- A repeated idempotency key with the same payload returns the original result. A changed payload using the same key is rejected. Enforce uniqueness in PostgreSQL to handle concurrent requests.
- A rule-service timeout or invalid rule decision does not create a completed posting.
- Saving and reading monetary values preserves decimal precision. Dashboard totals do not combine different currencies.
- Gateway paths and internal client paths agree; errors retain a useful correlation identifier.
- Cloud Run calls use caller service identities and audience-specific identity tokens. Keep end-user authentication headers separate from platform invocation authentication where needed.
- Local hostnames are replaced by provider HTTPS URLs in cloud configuration. No Eureka server or Eureka client dependency is present.

## Information needed before cloud deployment

| Detail | Current state / action |
| --- | --- |
| GitHub account | Connector authenticated as `vijayabhargavidba` |
| Repository | Public sample-data repository `vijayabhargavidba/account-posting-demo` authorized |
| GCP project ID | `ledgermanager` (project number `434796230124`); access verified |
| GCP account | An active CLI account was found; use its existing authenticated session |
| GCP billing and permissions | Billing is enabled; verify deployment permissions before enabling APIs |
| Region | Cloud Run `us-east4` selected near the existing Neon AWS Ohio database |
| Neon database | Existing project `broad-firefly-45124778`, branch `br-dark-queen-b43vm0ap` (`production`), PostgreSQL 18; connection details pending |

Do not paste database passwords, personal access tokens or service-account keys into chat or commit them to Git. Provide non-secret project/repository/database identifiers when requested; enter secrets through local ignored configuration or the provider secret mechanism.

## Local prerequisite observations

- Workspace was initially empty and had no Git repository.
- Java 21 runtime verified at `C:\Program Files\Java\jdk-21.0.12.1`.
- Node.js 24.19.0 verified.
- Maven 3.9.9 verified using Java 21; npm 11.17.0 verified. Select Java 21 explicitly in project startup/build scripts rather than relying on the current Java launcher.
- Docker engine 29.7.2 verified with elevated tool execution after sandbox pipe access was denied.
- Google Cloud CLI is installed and has an active account. Ordinary sandbox execution cannot write its configuration/log directory; authorized elevated tool execution works.

## Same-day scope

### Verified local progress

- Created the Java services, React UI, Excel decision table, database migration, Docker configuration and Windows launcher scripts.
- All 16 backend tests passed: five rules tests, six PostgreSQL tests and five Gateway tests.
- React production build passed.
- `start.ps1` starts PostgreSQL in Docker and the Java services plus React on the host, waits for health checks and verifies the dashboard through Gateway.
- A synthetic posting was saved with its Excel-selected account; retrying it returned the same posting.
- Repeated startup reused the same processes. `stop.ps1` stopped only the recorded application processes and the demo database container.
- Restarting retained the saved posting. All five application processes and PostgreSQL were healthy at the end of verification.
- Process identity validation rejected mismatched start times and entrypoints. Runtime records and logs remain in ignored `.local` storage.

Remaining: browser visual/interaction review, container-image verification, GitHub publication, Neon connection/secrets configuration, GCP deployment and cloud smoke testing. GCP project and billing access are verified. No application services have been deployed to GCP yet.

Target a working local and deployed demonstration of one complete posting workflow. Include validation, database migrations, duplicate protection, decision audit, basic tests and usable UI states. Use the packaged sample rules for this first version. A rule-upload/approval interface, advanced reporting and integration with existing production systems can follow after the complete demo works.

Cloud Run has usage-based charges beyond its free allowances; builds, registry storage and data transfer can have separate costs. Start with request-based billing, minimum instances zero and a small maximum instance limit, and review the chosen project's billing before deployment. These settings are not a hard spending cap.
