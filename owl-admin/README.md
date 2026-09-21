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
bundle exec rspec
bin/rubocop
```

### Testing

RSpec (`rspec-rails` + `factory_bot_rails` + `shoulda-matchers`), not Rails'
default Minitest — `spec/models` and `spec/requests` cover every model and
every controller, plus `spec/services`. Request specs (not controller specs —
the modern RSpec-Rails default) exercise full routing + middleware, same as
the old `ActionDispatch::IntegrationTest` suite did.

`spec/rails_helper.rb` force-sets `RAILS_ENV=test` **unconditionally** (not
`||=`): `Dockerfile.dev` hardcodes `ENV RAILS_ENV=development` for the dev
container, and only an unconditional assignment overrides that (`bin/rails
test` used to paper over this the same way, internally). Skipping this makes
every request spec 403 against the dev host allowlist and run against the dev
database instead of the test one — a real, easy-to-reintroduce trap if this
file is ever regenerated.

`spec/support/scholarship_helpers.rb`'s `create_scholarship` (not a
`Scholarship` factory) exists because `Scholarship` reads owl-api's table over
a second, unmanaged connection (`database_tasks: false`) that transactional
fixtures don't reliably wrap — each spec using it cleans up exactly the rows
it made in an `after` hook, the same workaround the old Minitest suite used.
`include_context "signed in admin"` (`spec/support/signed_in_admin.rb`) gets a
signed-in `admin` in a request spec.

## API

| Route | Auth | Purpose |
| --- | --- | --- |
| `POST /api/registrations` | none | Sign up — `{ email, password }` → `{ token, user }`. |
| `POST /api/session` | none | Log in — same shape as above. |
| `DELETE /api/session` | none | Log out (stateless; the client just drops the token). |
| `POST /api/conversations` | Bearer | Start a conversation for the current user. |
| `GET /api/conversations/:id` | Bearer | Fetch a conversation with its messages. |
| `POST /api/conversations/:id/messages` | Bearer | **SSE.** Persists the user turn, relays owl-api's stream (`user_message`, `routing`, `token`×N, `done` / `error`), then persists the assembled answer with its `agent` (`general_advisor` / `scholarship_expert`) and `trace_run_id` (from `done.run_id`). `ActionController::Live`. **503** if `AI_SCHOLARSHIP_AGENT` is off. |
| `POST /api/messages/:id/feedback` | Bearer | `{ rating: "up" \| "down", reason? }` — one row per message; a second call updates it in place. |
| `GET /api/features` | none | `{ ai_scholarship_agent: bool }` — which screen owl-web should render. Not sensitive; public on purpose. |
| `GET /api/scholarships`, `GET /api/scholarships/:id` | Bearer | List/search (`?q=`) or fetch one row of the shared `scholarships` table — the browse screen owl-web shows when the flag above is off. |
| `GET /.well-known/jwks.json` | none | Publishes the RSA public key `owl-api` verifies against. |

Two JWT audiences, both signed RS256 by `JwtService`: `aud: "owl-admin"` for the
browser's session (`Authorization: Bearer <token>` on every `/api` call), and a
5-minute `aud: "owl-api"` token `OwlApiClient` mints per outbound call. The
browser only ever talks to owl-admin; owl-admin is owl-api's HTTP client for
streaming a turn (now also sending `user_id`, so the agent can key its
profile store), `.ingest` from `scholarships:seed`, the scraper, and the admin
scholarship edit form.

### `Internal::` — the reverse direction

owl-api also calls *back* into owl-admin, for the two things only owl-admin's
database has: the `users` table and the full conversation transcript. Auth is
a shared secret rather than JWT/JWKS (`InternalAuthenticatable`, checked with
`ActiveSupport::SecurityUtils.secure_compare` against `OWL_INTERNAL_SECRET`) —
deliberately simpler than the RS256 scheme above, since this is two narrow
endpoints rather than a general trust boundary.

| Route | Auth | Purpose |
| --- | --- | --- |
| `GET /internal/users/:id/profile` | Shared secret | `{ full_name, email, phone, degrees }`. |
| `PATCH /internal/users/:id/profile` | Shared secret | Updates `full_name` / `phone` / `degrees` only — strong params deliberately exclude `email`, `encrypted_password`, `role`, so this agent-facing endpoint can never touch identity/auth fields. |
| `POST /internal/conversations/:id/email` | Shared secret | Sends `ConversationMailer.transcript` for that conversation to its owner's registered email. |

## Personal info fields

`users` gained `full_name`, `phone` (both plain strings), and `degrees` (a
Postgres string array, default `[]`) — a simple array over a separate model
since a student's degree list has no fields of its own yet. `User#profile_json`
is the shape both the `Internal::UsersController` responses and `owl-api`'s
`app/owl_admin_client.py` agree on.

## Emailing a conversation

`ConversationMailer#transcript` renders the full transcript (colored by role,
citations as links) and sends it to `conversation.user.email`. In development,
`config.action_mailer.delivery_method = :letter_opener_web` intercepts every
send into a local inbox instead of a real SMTP call (`letter_opener_web`, not
plain `letter_opener` — this container is headless, so the "pop a browser
tab open" behavior of the base gem doesn't work; the `_web` variant is a
mountable Rack engine instead). View it at **`/letter_opener`** (linked from
the sidebar as "Correos (dev)"), gated the same way `/admin/flipper` is —
signed-in admins only. `ApplicationMailer`'s `from` reads
`ENV["OWL_MAILER_FROM"].presence || "Owl <owl@example.com>"` — `.presence`,
not `ENV.fetch`, because docker-compose always defines the var (even as an
empty-string passthrough), so `.fetch`'s fallback would never trigger.

### Shared database: the `scholarships` table

There is **one** scholarship table in the whole system — owl-api's — and
owl-admin reads it directly over a second connection (`owl_api` in
`config/database.yml`, `database_tasks: false` so Rails never migrates it). The
`Scholarship` model (`< OwlApiRecord`) is read-only in practice: edits are sent
back through `OwlApiClient.ingest` so owl-api re-chunks and re-embeds. No local
copy, no sync state. `OWL_API_DATABASE_URL` points at it (a plain `postgres://`
URL — owl-api itself uses the `postgresql+psycopg://` form).

## Feature flags

[Flipper](https://www.flippercloud.io/docs) (`flipper` + `flipper-active_record`
+ `flipper-ui`), stored in this app's own Postgres — no Redis, no external
service. Flag names live in `app/services/features.rb`, one place instead of
scattered strings:

```ruby
Features::AI_SCHOLARSHIP_AGENT # => :ai_scholarship_agent
Features.ai_scholarship_agent?  # => Flipper.enabled?(...)
```

| Flag | On (default) | Off |
| --- | --- | --- |
| `AI_SCHOLARSHIP_AGENT` | owl-web shows the chat agent; each turn calls owl-api's LangGraph agent (OpenAI cost). | `POST /api/conversations/:id/messages` returns 503 without calling owl-api; owl-web shows a plain scholarship list + search bar instead (`GET /api/scholarships`). |

Manage it at **`/admin/flipper`** (linked from the sidebar as "Feature flags") —
signed-in admins only. It's a mounted Rack app (`Flipper::UI`), not an
`Admin::BaseController`, so it can't run a `before_action`; `config/routes.rb`
gates it with a `constraints` block that checks Warden directly, with a
redirect-to-login fallback for everyone else. `db/seeds.rb` turns
`AI_SCHOLARSHIP_AGENT` on by default (`Flipper.enable` is idempotent — safe to
re-run `db:seed`).

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
| `/admin/scholarships`, `/admin/scholarships/:id` | owl-api's `scholarships` table, read directly. Edit any wire field → owl-admin sends it to `OwlApiClient.ingest`, which re-chunks + re-embeds. |
| `/admin/sources` | Source-health panel — scholarship count (per host), last scrape, last status; toggle `enabled`. `Source` is owl-admin-only. |
| `/admin/users` | Users + conversation counts. |
| `/admin/messages/:id/annotation` | `Annotation` upsert — verdict (`good`/`bad`) + the ideal reply. The Phase 6 fine-tuning corpus. |
| `/admin/flipper` | Feature flags (see below) — Flipper's own management UI. |

### Fine-tuning export (Phase 6 scaffolding)

`make finetune-export` (→ `FineTuning::Exporter`) turns blessed turns — 👍,
`verdict: good`, or an `ideal_response` — into an OpenAI chat SFT JSONL under
`tmp/fine_tuning/`. Each answer message carries `generation` (jsonb:
`system_prompt`, `model_variant`), set from owl-api's `done` frame, so examples
are real `(system + context → answer)` pairs. Nothing is trained automatically —
the full loop is in [`../docs/fine-tuning.md`](../docs/fine-tuning.md).

### The scraper

`app/services/scholarship_scraper.rb` — fetches one page and pushes it to
owl-api's ingest endpoint. There is no local copy; owl-api's `scholarships`
table is the only store.

```ruby
# docker compose exec admin bin/rails console
ScholarshipScraper.new("https://www.chevening.org/scholarship/colombia/").scrape
# => { scholarship_id: "9", chunks: 5, action: "created" }

ScholarshipScraper.new(url).scrape(dry_run: true)    # extract only, no writes
ScholarshipScraper.new(url, html: "<html>…").scrape  # skip the fetch
```

Fetches the page (`Net::HTTP`, ≤3 redirects, HTML-only), does **generic**
readability extraction (strips `script`/`nav`/`footer`/…, headings → `#`, list
items → `-`), `POST`s to `/v1/scholarships/ingest`, and stamps the matching
`Source` row (`last_scraped_at` / `last_status`). `fields` / `levels` come back
empty (no per-site parser, no LLM): fill them in the admin edit form. Raises
`ScholarshipScraper::Error` on a bad URL, a non-HTML response, or a body too
short to be real content.

owl-api computes `content_hash` from the wire fields when the caller omits it,
so any edited field re-triggers a re-embed; identical content returns
`unchanged`.

## Environment

| Var | Meaning |
| --- | --- |
| `DATABASE_URL` | Postgres connection (development / production). |
| `TEST_DATABASE_URL` | Postgres connection for the test suite. |
| `OWL_API_URL` | Base URL of owl-api for server-to-server HTTP calls. |
| `OWL_API_DATABASE_URL` / `OWL_API_TEST_DATABASE_URL` | owl-api's Postgres — owl-admin reads the `scholarships` table from it directly (plain `postgres://` URL). |
| `OWL_WEB_ORIGINS` | Comma-separated CORS allow-list (defaults to the Vite dev server). |
| `LANGSMITH_HOST` / `LANGSMITH_PROJECT` | Only used to build the transcript's "trace ↗" links — match owl-api's project. |
| `ADMIN_PASSWORD` | Password for the `admin@example.com` account `db/seeds.rb` creates (default `password123`). |
| `RAILS_MASTER_KEY` | Production only; provided from SSM. Dev reads `config/master.key`. |
| `OWL_JWT_PRIVATE_KEY` | Production only (PEM, from SSM). Dev generates and caches `config/jwt/private_key.pem`. |
| `OWL_INTERNAL_SECRET` | Shared secret owl-api sends as a bearer token on `Internal::` requests — must match the same var in owl-api's environment. |
| `OWL_MAILER_FROM` | `From:` address for `ConversationMailer` (optional; defaults to `Owl <owl@example.com>`). |

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

- **Phase 3** — `ScholarshipScraper` + a `Source` model exist. Still to come:
  GoodJob + a "Run crawl" action, per-site parsers, a scheduled crawl, and a
  per-run report. (A local `ScholarshipRecord` copy was built in Phase 5 then
  removed — one shared `scholarships` table instead.)
- **Phase 4 (done, mostly in owl-api)** — the graph routes to a
  `scholarship_expert` node; owl-admin relays the `routing` frame and persists
  `message.agent`.
- **Phase 5 (done)** — the `/admin` app: auth, conversation browser + trace
  links, satisfaction dashboard, scholarship inventory with edit + re-push,
  source-health panel, annotation view.
- **Phase 6 (scaffolding done)** — `make finetune-export`, `messages.generation`,
  the A/B seam in owl-api. Waiting on real annotation data before a job runs.
- **Agent memory (done, cross-cutting)** — `Internal::UsersController` /
  `Internal::ConversationsController` (shared-secret auth), `full_name` /
  `phone` / `degrees` on `users`, `ConversationMailer` + the dev-only
  `/letter_opener` inbox. Lets owl-api's agent save/recall a student's profile
  across conversations and email a transcript on request — see owl-api's
  README for the graph side.
