-- Example init.sql: runs on first container start only.
-- Creates common extensions and a simple demo table in the application DB.

-- Enable useful extensions (safe if already present)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Demo schema/table to show initialization works
CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.example_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Grant ownership/privileges to the app user
ALTER TABLE app.example_items OWNER TO CURRENT_USER;
GRANT USAGE ON SCHEMA app TO CURRENT_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA app TO CURRENT_USER;
