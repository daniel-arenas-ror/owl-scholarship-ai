# syntax=docker/dockerfile:1

FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# --- development: Vite dev server with HMR (used by docker-compose) ----------
FROM node:24-alpine AS dev
WORKDIR /app
ENV NODE_ENV=development
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN chmod +x docker-entrypoint.sh
ENTRYPOINT ["./docker-entrypoint.sh"]
EXPOSE 5173
CMD ["npm", "run", "dev"]

# --- build: produce the static bundle --------------------------------------
FROM deps AS build
ARG VITE_ADMIN_API_URL
ARG VITE_OWL_API_URL
ENV VITE_ADMIN_API_URL=$VITE_ADMIN_API_URL \
    VITE_OWL_API_URL=$VITE_OWL_API_URL
COPY . .
RUN npm run build

# --- static: Caddy serving the SPA (the image pushed to ECR) --------------
FROM caddy:2-alpine AS static
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
EXPOSE 80
