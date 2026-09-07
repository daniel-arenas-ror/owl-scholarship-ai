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

| Var                  | Meaning                                                       |
| -------------------- | ----------------------------------------------------------- |
| `VITE_ADMIN_API_URL` | Base URL of owl-admin — the only backend the browser talks to. |

## What's here

- `AuthForm.tsx` — register / log in, toggled from one form.
- `Chat.tsx` — starts a conversation, then per turn makes **one** request to
  owl-admin and consumes the SSE stream it relays back (owl-admin persists
  both messages itself). Renders the live token stream, a "🎓 Consultando la
  ficha de …" chip when the turn is routed to the scholarship expert, an
  "Experto en …" label on expert answers (the scholarship name comes from the
  answer's single citation), and the 👍/👎 feedback buttons.
- `api.ts` — `sendMessage` is the one non-obvious piece: SSE-_shaped_
  streaming built on `fetch` + a manually-read `ReadableStream`, not the
  native `EventSource` API. `EventSource` is GET-only with no request body or
  custom headers — this needs both. Events: `routing` (which agent took the
  turn), `user_message`, `token`×N, then `done` (the persisted assistant
  message) or `error`.
- `useAuth.ts` — holds the JWT + user in `localStorage` so a reload stays
  logged in.

## Styling

Tailwind v4, configured CSS-first in `src/index.css`. The `@theme` block there is
the shared Owl palette — keep it in sync with
`owl-admin/app/assets/tailwind/application.css`.

## Testing notes

`src/setupTests.ts` patches two jsdom/Node gaps that would otherwise break
tests, not app bugs: a real `localStorage` (recent Node versions ship their own
experimental one that shadows jsdom's and is missing methods) and a no-op
`Element.prototype.scrollIntoView` (jsdom doesn't implement layout at all).

`Chat.test.tsx` fakes the SSE stream with a real `Response`/`ReadableStream`
pair (both are genuine Node globals here, not mocks) so the actual
event-parsing loop in `api.ts` runs for real in the test.

## Production

`docker build --target static` produces a `caddy:2-alpine` image that serves
`dist/` with SPA fallback. That image is what CI pushes to ECR.
