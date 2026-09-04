# owl-admin

Ruby on Rails 8 + Tailwind CSS. Identity provider, conversation store,
manually-triggered scraper, and the admin-only dashboards.

## Run with the rest of the stack

From the repo root: `make up` → http://localhost:3000 (`/up` for the health check).

## Run on its own

Needs Postgres reachable at `DATABASE_URL` (defaults to
`postgres://owl:owl@localhost:5432/owl_admin`).

```bash
bundle install
bin/rails db:prepare
bin/dev            # Puma + Tailwind watcher (http://localhost:3000)
bin/rails test
bin/rubocop
```

## API (Phase 1)

| Route | Auth | Purpose |
| --- | --- | --- |
| `POST /api/registrations` | none | Sign up — `{ email, password }` → `{ token, user }`. |
| `POST /api/session` | none | Log in — same shape as above. |
| `DELETE /api/session` | none | Log out (stateless; the client just drops the token). |
| `POST /api/conversations` | Bearer | Start a conversation for the current user. |
| `GET /api/conversations/:id` | Bearer | Fetch a conversation with its messages. |
| `POST /api/conversations/:id/messages` | Bearer | Post a user message; owl-admin calls owl-api and returns both turns. |
| `GET /.well-known/jwks.json` | none | Publishes the RSA public key `owl-api` verifies against. |

Auth is a single JWT scheme reused for two audiences: `aud: "owl-admin"` for the
browser's own session (`Authorization: Bearer <token>` on every `/api` call),
and a 5-minute `aud: "owl-api"` token `OwlApiClient` mints per request for the
server-to-server call. Both are signed RS256 by `JwtService`.

## Seeding scholarships

```bash
make up      # in another terminal — must already be running
make seed    # or: docker compose run --rm admin bin/rails scholarships:seed
```

`docker compose run` only starts *this* container's own `depends_on`
(Postgres) — it won't bring up `api` as a side effect, since `admin` doesn't
declare a dependency on it. So `make seed` (or a bare `bin/rails
scholarships:seed` outside Docker) needs owl-api already reachable, or every
scholarship fails with `Failed to open TCP connection to api:8000`.

Reads `db/seeds/scholarships.json` (8 real, well-known programs — ICETEX,
Colfuturo, Chevening, DAAD, Fulbright, Erasmus Mundus, MinCiencias, Eiffel —
marked as example/seed data with a "verify on the official site" note baked
into each entry) and pushes each one through `OwlApiClient.ingest`, which
chunks, embeds, and stores it in owl-api's pgvector. Needs a real
`OPENAI_API_KEY` in `.env` — owl-api returns 503 without one. Idempotent: a
second run reports `unchanged` for anything whose content hasn't changed.

## Environment

| Var | Meaning |
| --- | --- |
| `DATABASE_URL` | Postgres connection (development / production). |
| `TEST_DATABASE_URL` | Postgres connection for the test suite. |
| `OWL_API_URL` | Base URL of owl-api for server-to-server calls. |
| `OWL_WEB_ORIGINS` | Comma-separated CORS allow-list (defaults to the Vite dev server). |
| `RAILS_MASTER_KEY` | Production only; provided from SSM. Dev reads `config/master.key`. |
| `OWL_JWT_PRIVATE_KEY` | Production only (PEM, from SSM). Dev generates and caches `config/jwt/private_key.pem`. |

## Styling

Tailwind v4 via `tailwindcss-rails` (standalone CLI, no Node). The `@theme` block
in `app/assets/tailwind/application.css` is the shared Owl palette — keep it in
sync with `owl-web/src/index.css`.

## Known Phase 1 shortcut

No Alembic-style migration discipline needed here — Rails migrations already do
that job properly. The shortcut is on the owl-api side (see its README).

## Docker

- `Dockerfile.dev` — used by docker-compose (bind mount + `bin/dev`).
- `Dockerfile` — production build (Rails default: multi-stage, Thruster, non-root). CI pushes this to ECR.

## Roadmap

- **Phase 2** — streaming, per-message feedback, LangGraph checkpointer.
- **Phase 3** — GoodJob + the "Run crawl" action and `Source` model.
- **Phase 5** — the admin dashboards (conversations, satisfaction, inventory).
