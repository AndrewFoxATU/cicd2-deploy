# Production Plan: Tyre Shop System

Goal: take the six-repo school project (tyres, users, orders, notifications, frontend, deploy)
and make it safe and reliable enough to run the real business on.

This plan is based on a review of the actual code as of July 2026. Phases are ordered by risk:
each phase is shippable on its own, and nothing later depends on skipping something earlier.

---

## Where the project stands today

What already works well:

- Clean microservice split: FastAPI services (tyres, users, orders) each with their own
  Postgres database, a RabbitMQ-driven notifications worker, and a Next.js frontend.
- CI on every service: pytest with an 80% coverage gate, then Docker image build and push
  to GHCR, tagged `latest` + commit SHA.
- Sales flow works end to end: orders service checks the seller and stock over HTTP,
  decrements stock, records the sale, and publishes `sale.created` to a topic exchange.

What blocks real-world use (found in the code):

| # | Issue | Where |
|---|-------|-------|
| 1 | Live CloudAMQP credentials committed to git in `.env` | `cicd2-deploy/.env` |
| 2 | Passwords stored in **plaintext**; login compares raw strings | `users-service app/models.py`, `app/main.py` login endpoint |
| 3 | No sessions or tokens — login returns the user object; every API endpoint is unauthenticated, so anyone who can reach the API can delete users/tyres | all services |
| 4 | Roles (`admin/employee+/employee`) exist on the user model but are never enforced server-side | users service + frontend |
| 5 | Login state lives only in React state — a page refresh logs you out | `frontend store/globalContext.js` |
| 6 | Schema managed by `Base.metadata.create_all()` — no migrations, so schema changes on a live database are manual and risky | all services |
| 7 | Sell flow is not atomic: stock is decremented via PATCH, then the sale row is inserted. A crash in between loses stock; two simultaneous sells can both pass the stock check (read-then-write race) | `orders-service app/main.py` |
| 8 | Notifications worker only `print()`s — no actual email/SMS goes out | `notifications-service` |
| 9 | Deployment is manual `docker compose pull && up` with no HTTPS, no reverse proxy, no backups, no monitoring, and Postgres ports published to the host | `cicd2-deploy` |
| 10 | CORS pinned to `http://localhost:3000`; will break behind a real domain | tyres + users services |

---

## Phase 0 — Security triage (do immediately, ~1 day)

> **Status: done in code** — `.env` untracked, ports closed, `.env.example` added.
> The credential rotation steps (CloudAMQP, Postgres) are manual: see `SECURITY.md`.

These are cheap and urgent; everything else can wait, this can't.

1. **Rotate the CloudAMQP credentials** (the current ones are public to anyone with repo access),
   then remove `.env` from git tracking, add it to `.gitignore`, and scrub it from git history
   (`git filter-repo`). Keep a committed `.env.example` with names only.
2. Rotate the Postgres passwords at the same time (they're weak and also committed).
3. Stop publishing Postgres ports (`5432-5434`) in docker-compose — services reach the DBs
   over the internal network; the host doesn't need them exposed.
4. Run GitHub secret scanning on all six repos to catch anything else.

## Phase 1 — Real authentication & authorization (~1–2 weeks)

> **Status: done** — bcrypt hashing (with transparent upgrade of legacy plaintext rows
> on first login), JWT login, httpOnly-cookie sessions in the frontend, server-side
> role enforcement on every endpoint, orders→tyres/users service tokens, CORS from env.

The system manages money and stock, so this comes before any new features.

1. **Hash passwords** with bcrypt/argon2 (`passlib`) in the users service; add a one-time
   migration to hash existing rows and force a password reset.
2. **Issue JWTs on login** (short-lived access token). The Next.js API routes already proxy
   every backend call, so store the token in an httpOnly cookie set by `login-user.js` —
   this also fixes the lost-login-on-refresh problem for free.
3. **Enforce auth on every backend endpoint**: shared FastAPI dependency that validates the
   JWT; reject unauthenticated requests. Role checks server-side: only `admin` can manage
   users, only `admin`/`employee+` can modify inventory, anyone logged in can sell.
4. Fix CORS to come from an `ALLOWED_ORIGINS` env var instead of hardcoded localhost.

## Phase 2 — Data integrity & correctness (~1–2 weeks)

> **Status: done** (except the cross-service CI smoke test, deferred) — Alembic
> migrations in all three services with automatic baseline stamping of existing
> databases; atomic conditional stock decrement in the tyres service with
> compensation from the orders service; DB CHECK constraints; `RETAIL_MARKUP`
> is now configuration; sale event publishing is best-effort so a broker outage
> can't fail a stored sale.

1. **Alembic migrations** in each service; replace `create_all()` with a migration step in
   the container entrypoint (or a deploy step). This is the prerequisite for every future
   schema change on live data.
2. **Fix the sell race/atomicity**: move the stock decrement into the tyres service as a
   single conditional update (`UPDATE ... SET quantity = quantity - :n WHERE id = :id AND
   quantity >= :n`, returning 409 if no row matched) — one atomic operation instead of
   read-check-patch. On sale-insert failure after decrement, compensate by restoring stock.
3. Add input constraints that a business needs: non-negative quantities and costs at the DB
   level, unique tyre (brand, model, size, supplier) if that matches how the shop thinks
   about stock.
4. Make the 1.35 retail markup a configuration value, not a magic number in two endpoints.
5. Bring orders service tests up to the same standard as tyres/users (there is a suite, but
   the sell edge cases above need coverage), and add one cross-service smoke test that runs
   the full sell flow against docker-compose in CI.

## Phase 3 — Production environment (local-only, ~2–4 days)

> **Decision: the business runs this on a machine in the shop — no paid servers.**
> That removes the domain/HTTPS/VPS work entirely. The trade-offs to accept: the app
> is only reachable on the shop network, and that machine is now a business-critical
> box (keep it on, keep it backed up).

> **Status: done in code** — self-hosted RabbitMQ container (CloudAMQP no longer
> needed), healthchecks + `restart: unless-stopped` on every service, API/broker
> ports bound to 127.0.0.1, README rewritten with setup/update/backup instructions.

1. ~~Buy a domain / reverse proxy / HTTPS~~ — not needed while local-only. The frontend
   is served on the LAN over HTTP; revisit if the business ever wants remote access
   (then: Tailscale first, public VPS second).
2. **RabbitMQ self-hosted** in compose (`rabbitmq:3-management`) — no external account,
   and deleting the old CloudAMQP instance revokes the leaked credential for good.
3. **Deployment** stays manual and simple: `docker compose pull && docker compose up -d`
   after CI publishes new images. No SSH automation needed for a machine you can walk to.
4. **Backups are still non-negotiable**: a scheduled (cron / Task Scheduler) `pg_dump`
   of all three databases, copied to a USB drive or free-tier cloud storage — an
   off-machine copy is the whole point. Test the restore once.
5. Make the shop machine resilient: Docker set to start on boot (compose services
   already have `restart: unless-stopped`), disable sleep/hibernate.

## Phase 4 — Make notifications real (~3–5 days)

1. Wire the notifications worker to an email provider (Resend/Postmark/SES — pick by price,
   all have simple APIs) so `sale.created` actually sends a receipt/alert.
2. Add a dead-letter queue and retry policy so a failed send doesn't drop the message, and
   make queue consumption idempotent (dedupe on `sale_id`).
3. Decide recipients with the business: owner gets sale alerts? customer gets a receipt
   (needs a customer email captured at sale time — small schema + UI addition)?

## Phase 5 — Observability & operations (lightweight, local-only)

External uptime monitoring makes little sense for a LAN-only app; keep this lean:

1. Error tracking (Sentry free tier) in the FastAPI services and Next.js — still worth
   it, it works fine from a local machine and catches bugs staff never report.
2. `docker compose ps` health status is the uptime check; healthchecks are already in
   place. A tiny cron job that restarts unhealthy containers and appends to a log file
   covers the rest.
3. A one-page `RUNBOOK.md` in cicd2-deploy: update, roll back (pin a SHA image tag),
   restore a backup, rotate a secret, check the RabbitMQ management UI.

## Phase 6 — Business features (after go-live, prioritise with the owner)

Not needed for go-live, listed for the roadmap conversation:

- Sales history & reporting (orders DB already stores every sale — a `/api/sales` listing
  endpoint and a frontend report page is the quick win; daily/weekly totals next).
- VAT/tax handling on prices and receipts.
- Low-stock alerts (reuse the notifications pipeline with a `stock.low` event).
- Supplier purchase orders / restocking workflow.
- Customer records attached to sales (also enables receipts by email).
- Audit log of who changed prices/stock (the JWT identity from Phase 1 makes this possible).

---

## Suggested timeline

| Weeks | Work |
|-------|------|
| Week 1 | Phase 0 (day 1) + start Phase 1 |
| Weeks 2–3 | Finish Phase 1, Phase 2 |
| Weeks 4–5 | Phase 3 (go-live at end, with auth + backups + HTTPS in place) |
| Week 6 | Phases 4–5 |
| Ongoing | Phase 6 features, prioritised with the business |

## Decisions needed from the business side

1. ~~Hosting budget~~ — **decided: local-only on a shop machine, €0/mo.**
2. ~~Domain name~~ — not needed while local-only.
3. Email provider and who receives sale notifications (owner alert vs customer receipt vs
   both). Free tiers (e.g. Resend, Brevo) send fine from a local machine.
4. Whether sales need customer details/VAT receipts from day one (affects Phase 2 schema).
5. ~~RabbitMQ hosting~~ — **decided: self-hosted container in compose; delete the CloudAMQP account.**
6. Which machine in the shop runs the stack, and where the nightly backup copy goes
   (USB drive vs free cloud storage).
