# Sahayak — home-services marketplace (India)

Two-sided marketplace: customers book household services (cleaning, plumbing, electrical,
carpentry, appliance repair), nearby verified providers accept and fulfil them, with live
tracking, cash on delivery, invoices and ratings.

> **Working name.** "Sahayak" is a placeholder brand — replace it before store submission.

| Part | Stack | Folder |
|---|---|---|
| API | Java 21, Spring Boot 3.5 (modular monolith, Spring Modulith), MySQL 8.4, Flyway | `backend/` |
| Mobile app (customer + provider) | React Native (Expo SDK 54), TypeScript | `mobile/` |
| Admin web | React + Vite (Milestone 6) | `admin/` (later) |
| Design docs | Requirements → deployment | `docs/` |

## Design package

| Doc | Contents |
|---|---|
| [01 — Requirements & decisions](docs/01-requirements-and-decisions.md) | Confirmed requirements, every default decision, assumptions, seed prices, prioritised MVP scope |
| [02 — Roadmap & journeys](docs/02-roadmap-and-journeys.md) | Milestones M1–M7 with exit criteria; customer / provider / admin journeys |
| [03 — Architecture](docs/03-architecture.md) | Modules → future services, outbox/inbox, sagas, consistency, resilience, extraction plan, dispatch/location/pricing/payment design, deployment topology |
| [04 — Database](docs/04-database.md) | Data ownership, full DDL for all modules, indexes, booking state machine, retention |
| [05 — API & events](docs/05-api-and-events.md) | REST conventions, error format, auth flow, authz rules, endpoint map, event contracts |
| [06 — Frontend & security](docs/06-frontend-and-security.md) | Screen map, design system, accessibility, security plan, DPDP privacy plan |
| [07 — Ops, testing, deployment](docs/07-ops-testing-deployment.md) | Observability, testing strategy, CI/CD, environments, third-party services & costs |

## Milestone 1 (this delivery): foundation + identity

**Backend**
- Modular monolith skeleton: `identity`, `audit`, `shared` modules; boundaries verified by `ModuleStructureTest`.
- Auth: separate customer/provider registration & login, admin login, 6-digit email verification
  codes (HMAC-hashed, 15 min, 5 attempts, 60 s resend cool-down), JWT access tokens (15 min),
  rotating opaque refresh tokens (hashed, reuse detection revokes the whole session family),
  logout / logout-all, forgot / reset / change password, Argon2id hashing, common-password deny
  list, account lockout (5 failures → 15 min), per-IP and per-email rate limits, no account enumeration.
- Transactional outbox + relay (SKIP LOCKED, backoff, dead-letter) and idempotent inbox; audit
  module records every domain event plus security events (failed logins, token reuse).
- RFC 9457 errors with stable `code`, correlation IDs, PII-masked logs, ECS JSON logs in prod,
  Prometheus metrics, tracing IDs, health probes, OpenAPI/Swagger UI.
- Flyway migrations per module, Docker image, Docker Compose stack, GitHub Actions CI.

**Mobile**
- Role choice → role-specific login/register → email code verification (auto-submit) →
  role-based tabs (customer vs provider). Forgot/reset password. Account screen with logout.
- Tokens in SecureStore (Keychain/Keystore); API client with timeouts, single-flight refresh,
  proactive refresh, typed Problem Details errors; offline banner; error boundary;
  client validation mirroring the server; accessible components (labels, live regions, 48-dp targets).

## Verification status — read this

Be clear about what has and hasn't been run:

| Item | Status |
|---|---|
| Mobile validation + API-client logic (14 tests: refresh single-flight, session expiry, business 401s, Problem Details mapping, timeouts, phone normalisation, password rules) | ✅ **Executed and passing** (Node 22, run through a minimal Jest-compatible shim because npm was unreachable in the build sandbox) |
| Backend Java sources | ⚠️ **Syntax-checked only** (`javac` parse passes; all internal cross-references resolve). **Not yet compiled against Spring or run** — Maven Central was unreachable in the build sandbox |
| Backend unit tests (`*Test`) and integration tests (`*IT`, 36 cases on real MySQL via Testcontainers) | ⚠️ **Written, not yet executed** |
| Mobile Jest suite incl. `LoginScreen.test.tsx`, `tsc`, ESLint | ⚠️ **Written, not yet executed** |
| Maestro E2E flow (`mobile/e2e/`) | ⚠️ **Written, not yet executed** |
| Dependency versions in `pom.xml` / `package.json` | ⚠️ Chosen from known releases; first build may need a version bump (`npx expo install --fix` for mobile) |

The next step is to run `mvn verify` and `npm test`, fix anything that fails, and only then
mark Milestone 1 complete.

## Running locally

On this Windows setup, double-click `start-local.bat`. It starts Docker Desktop services,
the API and the browser app, then opens the app. Keep the API and web terminal windows open
while using Sahayak. The local MySQL container uses port 3307 so it does not replace or
interfere with a MySQL already installed on the computer.

To start services manually or on another operating system:

### Prerequisites
Java 21, Maven 3.9+, Docker, Node 22, and Android Studio (emulator) or Xcode (simulator).

### 1. Start infrastructure
```bash
docker compose up -d mysql redis mailpit
```
Mailpit inbox (where verification emails land): http://localhost:8025

### 2. Run the API
```bash
cd backend
mvn spring-boot:run -Dspring-boot.run.profiles=local
```
- Swagger UI: http://localhost:8080/swagger-ui.html
- Health: http://localhost:8080/actuator/health
- A bootstrap admin is created from `application-local.yml` (`admin@sahayak.local` / `Sahayak-Local-2026`).

Or run everything in containers: `cp .env.example .env`, fill `JWT_SECRET`, `CODE_PEPPER`
(`openssl rand -base64 48`) and `ADMIN_BOOTSTRAP_PASSWORD`, then `docker compose --profile app up -d --build`.

### 3. Run the mobile app
```bash
cd mobile
cp .env.example .env          # set EXPO_PUBLIC_API_URL (10.0.2.2 for Android emulator)
npm install
npx expo install --fix        # aligns native package versions to the installed Expo SDK
npx expo run:android          # or: npx expo run:ios, or `npx expo start` with Expo Go
```

### 4. Run the browser app
In a second terminal, start the API and local services first, then run:
```bash
cd web
npm install
npm run dev
```
Open http://localhost:5173. The browser app supports customer/provider registration, email
verification, sign-in, password reset, and account sign-out. Verification and reset codes are
delivered to the local Mailpit inbox at http://localhost:8025.

The current API milestone implements identity and account security only. Service bookings,
provider job listings, and payments are not implemented yet; the browser dashboard identifies
these as upcoming rather than creating fake bookings.

### 5. Manual smoke test (Milestone 1)
1. Welcome → **I need a service** → Create an account.
2. Open Mailpit, copy the 6-digit code, enter it → you land on the customer Home tab.
3. Account → Log out → log back in.
4. Repeat with **I'm a service professional** → you land on the provider Jobs tab.
5. Try logging into the customer flow with the provider account → "Invalid email or password".
6. Forgot password → code from Mailpit → new password → log in.

### Try the API with curl
```bash
curl -s -X POST localhost:8080/api/v1/auth/customers/register -H 'Content-Type: application/json' \
  -d '{"fullName":"Ananya Rao","email":"ananya@example.com","password":"Sahayak#2026pass","phone":"+919876543210"}'
# read the code in Mailpit, then:
curl -s -X POST localhost:8080/api/v1/auth/verify-email -H 'Content-Type: application/json' \
  -d '{"email":"ananya@example.com","code":"123456"}'
```

## Testing

```bash
cd backend && mvn verify      # unit + module-boundary + Testcontainers integration tests (needs Docker)
cd mobile  && npm test        # Jest (validation, API client, LoginScreen)
cd mobile  && npm run typecheck && npm run lint
maestro test mobile/e2e/register-verify-login.yaml -e EMAIL=e2e-$(date +%s)@example.com
```

What the backend integration tests cover (`AuthFlowIT`, `OutboxAuditIT`): registration and
verification (wrong/expired/exhausted codes, resend cool-down, single-use codes), duplicate
emails (case-insensitive), validation error shape, common-password rejection, malformed JSON,
role-specific login, identical errors for unknown email vs wrong password, lockout and unlock,
rate limiting, role gating by URL prefix, tampered and expired JWTs, refresh rotation with
reuse detection, concurrent refresh with exactly one winner, logout / logout-all, password
reset (weak password doesn't burn the code, all sessions revoked), password change, correlation
IDs, outbox → audit delivery exactly once, and audit rows for failed logins without secrets.

## Code that depends on external credentials

| Feature | Needs | Local stand-in |
|---|---|---|
| Email | SMTP (AWS SES in prod) | Mailpit (compose) |
| Push (M3) | Firebase project + APNs key | in-app inbox |
| Maps (M2–M4) | Google Maps Platform keys | stub geo provider |
| SMS OTP (M7) | DLT registration + SMS vendor | none (email codes) |

## Project layout
```
backend/   Spring Boot API (com.sahayak.{shared,identity,audit}; more modules per milestone)
mobile/    Expo React Native app (src/{api,auth,components,navigation,screens,lib,theme})
web/       Browser app (registration, verification, login, password reset, account dashboard)
start-local.bat, start-local.ps1   Windows local startup launcher
docs/      Design package
.github/   CI pipeline
docker-compose.yml, .env.example
```
