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

## Environment

| Var | Meaning |
| --- | --- |
| `DATABASE_URL` | Postgres connection (development / production). |
| `TEST_DATABASE_URL` | Postgres connection for the test suite. |
| `OWL_API_URL` | Base URL of owl-api for server-to-server calls. |
| `OWL_INTERNAL_TOKEN` | Shared secret on the owl-admin → owl-api path (Phase 1: JWT). |
| `OWL_WEB_ORIGINS` | Comma-separated CORS allow-list (defaults to the Vite dev server). |
| `RAILS_MASTER_KEY` | Production only; provided from SSM. Dev reads `config/master.key`. |

## Styling

Tailwind v4 via `tailwindcss-rails` (standalone CLI, no Node). The `@theme` block
in `app/assets/tailwind/application.css` is the shared Owl palette — keep it in
sync with `owl-web/src/index.css`.

## Docker

- `Dockerfile.dev` — used by docker-compose (bind mount + `bin/dev`).
- `Dockerfile` — production build (Rails default: multi-stage, Thruster, non-root). CI pushes this to ECR.

## Roadmap

- **Phase 1** — Devise + `User`, RS256 JWT issuance + `/.well-known/jwks.json`,
  `Conversation` / `Message`, the `/api` endpoints owl-web calls.
- **Phase 3** — GoodJob + the "Run crawl" action and `Source` model.
- **Phase 5** — the admin dashboards (conversations, satisfaction, inventory).
