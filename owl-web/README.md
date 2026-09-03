# owl-web

React + TypeScript + Vite + Tailwind CSS v4. The chat UI.

## Run with the rest of the stack

From the repo root: `make up` → http://localhost:5173

## Run on its own

```bash
npm install
npm run dev        # http://localhost:5173
npm test           # vitest
npm run lint       # oxlint
npm run typecheck  # tsc
npm run build      # -> dist/
```

Environment (see `../.env.example`), read at build time, must be `VITE_`-prefixed:

| Var                  | Meaning                                                |
| -------------------- | ------------------------------------------------------ |
| `VITE_ADMIN_API_URL` | Base URL of owl-admin (auth, conversations, feedback). |
| `VITE_OWL_API_URL`   | Base URL of owl-api (the answer stream).               |

## Styling

Tailwind v4, configured CSS-first in `src/index.css`. The `@theme` block there is
the shared Owl palette — keep it in sync with
`owl-admin/app/assets/tailwind/application.css`.

## Production

`docker build --target static` produces a `caddy:2-alpine` image that serves
`dist/` with SPA fallback. That image is what CI pushes to ECR.
