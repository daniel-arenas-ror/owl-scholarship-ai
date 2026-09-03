-- Runs once, on first boot of an empty Postgres data directory.
-- Creates one database per service. pgvector is enabled per-database by each
-- service's own migrations (owl-api runs CREATE EXTENSION vector on startup).

CREATE DATABASE owl_api;
CREATE DATABASE owl_admin;

-- Rails also wants a *_test database.
CREATE DATABASE owl_admin_test;
