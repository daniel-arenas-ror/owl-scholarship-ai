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

| Var | Meaning |
| --- | --- |
| `VITE_ADMIN_API_URL` | Base URL of owl-admin (auth, conversations, feedback). |
| `VITE_OWL_API_URL` | Base URL of owl-api — unused until Phase 2 wires up direct SSE streaming. |

## What's here (Phase 1)

- `AuthForm.tsx` — register / log in, toggled from one form.
- `Chat.tsx` — starts a conversation on load, then a plain request/response
  loop against owl-admin (no streaming yet — that's Phase 2).
- `useAuth.ts` — holds the JWT + user in `localStorage` so a reload stays
  logged in.
- `api.ts` — a thin fetch wrapper for the four owl-admin endpoints this app
  calls.

## Styling

Tailwind v4, configured CSS-first in `src/index.css`. The `@theme` block there
is the shared Owl palette — keep it in sync with
`owl-admin/app/assets/tailwind/application.css`.

## Testing notes

`src/setupTests.ts` patches two jsdom/Node gaps that would otherwise break
tests, not app bugs: a real `localStorage` (recent Node versions ship their own
experimental one that shadows jsdom's and is missing methods) and a no-op
`Element.prototype.scrollIntoView` (jsdom doesn't implement layout at all).

## Production

`docker build --target static` produces a `caddy:2-alpine` image that serves
`dist/` with SPA fallback. That image is what CI pushes to ECR.
