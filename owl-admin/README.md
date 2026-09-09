# owl-admin

Ruby on Rails 8 + Tailwind CSS. Identity provider, conversation store,
scholarship inventory + scraper, and the admin-only app at `/admin`.

## Run with the rest of the stack

From the repo root: `make up` → http://localhost:3000 (`/up` for the health check).

The admin app lives at **http://localhost:3000/admin** (`/admin/login`). Create
an admin account with `make console` → `load "db/seeds.rb"` (idempotent; makes
`admin@example.com` / `password123`, override with `ADMIN_PASSWORD`), or
`docker compose exec admin bin/rails db:seed`.

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

## API

| Route | Auth | Purpose |
| --- | --- | --- |
| `POST /api/registrations` | none | Sign up — `{ email, password }` → `{ token, user }`. |
| `POST /api/session` | none | Log in — same shape as above. |
| `DELETE /api/session` | none | Log out (stateless; the client just drops the token). |
| `POST /api/conversations` | Bearer | Start a conversation for the current user. |
| `GET /api/conversations/:id` | Bearer | Fetch a conversation with its messages. |
| `POST /api/conversations/:id/messages` | Bearer | **SSE.** Persists the user turn, relays owl-api's stream (`user_message`, `routing`, `token`×N, `done` / `error`), then persists the assembled answer with its `agent` (`general_advisor` / `scholarship_expert`) and `trace_run_id` (from `done.run_id`). `ActionController::Live`. |
| `POST /api/messages/:id/feedback` | Bearer | `{ rating: "up" \| "down", reason? }` — one row per message; a second call updates it in place. |
| `GET /.well-known/jwks.json` | none | Publishes the RSA public key `owl-api` verifies against. |

Two JWT audiences, both signed RS256 by `JwtService`: `aud: "owl-admin"` for the
browser's session (`Authorization: Bearer <token>` on every `/api` call), and a
5-minute `aud: "owl-api"` token `OwlApiClient` mints per outbound call. The
browser only ever talks to owl-admin; owl-admin is owl-api's only client
(streaming a turn, or `.ingest` from `scholarships:seed`, the scraper, and the
admin "Enviar a owl-api" button).

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

## The admin app (`/admin`)

Session-cookie auth (`Admin::SessionsController`, no Devise views), gated to
`role: admin` by `Admin::BaseController`. Screens:

| Path | What |
| --- | --- |
| `/admin` | Headline counts + 👍 ratio + recent conversations. |
| `/admin/conversations`, `/admin/conversations/:id` | Every transcript, with the agent that answered, citations, the 👍/👎, a **trace ↗** link to LangSmith (`message.trace_run_id`), and an inline **annotation** form. |
| `/admin/satisfaction` | 👍 ratio overall, by agent, by cited scholarship, over time — Chartkick + Chart.js, pinned via importmap (no build step). |
| `/admin/scholarships`, `/admin/scholarships/:id` | The local `ScholarshipRecord` inventory. Edit any wire field, then **Enviar a owl-api** re-ingests it. |
| `/admin/sources` | Source-health panel — record count, last scrape, last status; toggle `enabled`. |
| `/admin/users` | Users + conversation counts. |
| `/admin/messages/:id/annotation` | `Annotation` upsert — verdict (`good`/`bad`) + the ideal reply. The Phase 6 fine-tuning corpus. |

### Scholarship inventory + the scraper

`ScholarshipRecord` is owl-admin's canonical copy of a scholarship; owl-api keeps
only the vectorized copy. **Records are created only by the scraper** —
`app/services/scholarship_scraper.rb`:

```ruby
# docker compose exec admin bin/rails console
ScholarshipScraper.new("https://www.chevening.org/scholarship/colombia/").scrape
# => #<ScholarshipRecord id: 1, last_push_status: "created", ...>

ScholarshipScraper.new(url).scrape(dry_run: true)    # extract only, no writes
ScholarshipScraper.new(url, html: "<html>…").scrape  # skip the fetch
```

It fetches the page (`Net::HTTP`, ≤3 redirects, HTML-only), does **generic**
readability extraction (strips `script`/`nav`/`footer`/…, headings → `#`, list
items → `-`), `upsert`s a `ScholarshipRecord` keyed by `source_url`, links a
`Source` (found/created by host), then `push_to_owl_api!` — chunk + embed +
store. `fields` / `levels` come back empty (no per-site parser, no LLM): fill
them in the admin edit form. Raises `ScholarshipScraper::Error` on a bad URL, a
non-HTML response, or a body too short to be real content.

`ScholarshipRecord#content_hash` is a digest of **every** wire field, so any
edit flips the record to "cambios sin enviar" until you push. owl-api dedupes on
that same hash (`created` / `updated` / `unchanged`).

## Environment

| Var | Meaning |
| --- | --- |
| `DATABASE_URL` | Postgres connection (development / production). |
| `TEST_DATABASE_URL` | Postgres connection for the test suite. |
| `OWL_API_URL` | Base URL of owl-api for server-to-server calls. |
| `OWL_WEB_ORIGINS` | Comma-separated CORS allow-list (defaults to the Vite dev server). |
| `LANGSMITH_HOST` / `LANGSMITH_PROJECT` | Only used to build the transcript's "trace ↗" links — match owl-api's project. |
| `ADMIN_PASSWORD` | Password for the `admin@example.com` account `db/seeds.rb` creates (default `password123`). |
| `RAILS_MASTER_KEY` | Production only; provided from SSM. Dev reads `config/master.key`. |
| `OWL_JWT_PRIVATE_KEY` | Production only (PEM, from SSM). Dev generates and caches `config/jwt/private_key.pem`. |

## Styling & JS

Tailwind v4 via `tailwindcss-rails` (standalone CLI, no Node). The `@theme` block
in `app/assets/tailwind/application.css` is the shared Owl palette — keep it in
sync with `owl-web/src/index.css`.

No build step: importmap only. Chartkick ships its own `chartkick.js` +
`Chart.bundle.js`, pinned in `config/importmap.rb` and imported from
`app/javascript/application.js` — nothing is fetched from a CDN.

## Known Phase 1 shortcut

No Alembic-style migration discipline needed here — Rails migrations already do
that job properly. The shortcut is on the owl-api side (see its README).

## Docker

- `Dockerfile.dev` — used by docker-compose (bind mount + `bin/dev`).
- `Dockerfile` — production build (Rails default: multi-stage, Thruster, non-root). CI pushes this to ECR.

## Roadmap

- **Phase 3** — `ScholarshipScraper` + `ScholarshipRecord` + `Source` exist
  (built with Phase 5). Still to come: GoodJob + a "Run crawl" action, per-site
  parsers, a scheduled crawl, and a per-run report.
- **Phase 4 (done, mostly in owl-api)** — the graph routes to a
  `scholarship_expert` node; owl-admin relays the `routing` frame and persists
  `message.agent`.
- **Phase 5 (done)** — the `/admin` app: auth, conversation browser + trace
  links, satisfaction dashboard, scholarship inventory with edit + re-push,
  source-health panel, annotation view.
- **Phase 6** — export the annotation corpus (`Annotation` → JSONL) for
  fine-tuning.
