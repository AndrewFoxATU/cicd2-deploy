# Security actions

## Done in this repo (Phase 0)

- `.env` is no longer tracked by git (see `.gitignore`); use `.env.example` as the template.
- Postgres containers no longer publish ports 5432–5434 to the host; services reach them
  over the internal `labnet` network only.
- `docker-compose.yml` now passes `JWT_SECRET` / `ALLOWED_ORIGINS` to the services (Phase 1 auth).
- The seeded default admin password in `postgres-init-users/admin.sql` is stored bcrypt-hashed.

## Manual actions still required (only the account owner can do these)

1. **Rotate the CloudAMQP credentials NOW.** The old `RABBIT_URL` (user `tgzsmwfa` on
   `stingray.rmq.cloudamqp.com`) was committed to git and must be treated as public.
   In the CloudAMQP console: rotate the password (or delete and recreate the instance),
   then put the new URL only in the server's local `.env`.
2. **Rotate the Postgres passwords** in `.env` (they were committed too):
   `openssl rand -hex 24` for each of `TYRES_DB_PASSWORD`, `USERS_DB_PASSWORD`,
   `ORDERS_DB_PASSWORD`. On an existing deployment also run `ALTER USER ... WITH PASSWORD ...`
   in each Postgres container, since the env var only applies on first init.
3. **Generate a JWT secret**: `openssl rand -hex 32` → `JWT_SECRET` in `.env`.
4. **Scrub `.env` from git history** once the credentials above are rotated
   (removing it from history without rotating gives false comfort):
   ```
   pip install git-filter-repo
   git filter-repo --invert-paths --path .env
   git push --force origin main
   ```
   Anyone with an old clone still has the old history — rotation is what actually
   revokes the secrets; the scrub just stops new clones from seeing them.
5. **Log in as `admin` (initial password `admin`) and change the password immediately**
   after first deployment.
