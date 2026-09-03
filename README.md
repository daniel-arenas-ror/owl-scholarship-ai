# Owl

A multi-agent assistant that helps Colombian students find the right scholarship.
Built as three deployed services in one repository.

| Folder | Stack | Role |
| --- | --- | --- |
| [`owl-web/`](owl-web/) | React + TypeScript + Vite + Tailwind CSS | Chat UI. Static bundle served by Caddy in production. |
| [`owl-admin/`](owl-admin/) | Ruby on Rails 8 + Tailwind CSS | Identity provider (Devise + JWT), conversation store, scraper, admin dashboards. |
| [`owl-api/`](owl-api/) | Python + FastAPI + LangGraph / LangChain | Retrieval, the multi-agent graph, LangSmith tracing, all OpenAI calls. |
| [`owl-infra/`](owl-infra/) | Terraform | Every AWS resource + the EC2 instance bootstrap. |

Full plan: **[Owl Build Roadmap](https://claude.ai/code/artifact/c374c30e-89cb-42e2-b239-c331cabc32c7)**

## Architecture (target)

Everything server-side — `owl-admin`, `owl-api`, Postgres 16 + pgvector, and a Caddy
reverse proxy that terminates HTTPS — runs as containers on **one AWS EC2 instance**
via `docker compose`. `owl-web` is a static bundle Caddy serves to the browser.

- `owl-web` → `owl-admin`: sign in, create conversations, post messages, submit feedback (REST).
- `owl-web` → `owl-api`: stream answer tokens directly (SSE), authorized by a short-lived token minted by `owl-admin`.
- `owl-admin` → `owl-api`: agent turns and scholarship ingest (server-to-server, RS256 JWT).
- `owl-admin`: an admin triggers a crawl by hand; GoodJob scrapes sources and posts normalized scholarships to `owl-api`, which embeds them into pgvector.

## Local development

Prerequisites: Docker Desktop (running), and for working outside containers:
Node 20+, Ruby 3.2+, Python 3.12+.

```bash
cp .env.example .env        # then fill in OPENAI_API_KEY at minimum
make setup                  # one-time: build images, create + migrate the database
make up                     # start Postgres + all three services
```

| URL | Service |
| --- | --- |
| http://localhost:5173 | `owl-web` (Vite dev server) |
| http://localhost:3000 | `owl-admin` (Rails) |
| http://localhost:8000 | `owl-api` (FastAPI) — `/health`, `/docs` |
| localhost:5433 | Postgres (`owl` / `owl`; databases `owl_api`, `owl_admin`) |

```bash
make down        # stop everything
make logs        # tail all services
make test        # run every test suite
make fmt lint    # format and lint every project
```

Each folder has its own README for running that service on its own.

## Deployment

CI builds an image per service, pushes it to Amazon ECR, and runs
`docker compose pull && up -d` on the EC2 instance over SSM — no SSH keys in CI.
See [`owl-infra/README.md`](owl-infra/README.md) for the one-time AWS setup.

## License

MIT — see [LICENSE](LICENSE).
