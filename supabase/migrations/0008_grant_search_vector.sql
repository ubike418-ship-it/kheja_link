-- =============================================================================
-- Kheja_Link — 0008_grant_search_vector.sql
--
-- 0006 granted SELECT column by column and left search_vector out. Postgres
-- requires SELECT on a column to *filter* by it as well as to read it, so
-- full-text search started failing with "permission denied for table
-- properties".
--
-- The column is an internal tsvector, not content, and no query ever asks for
-- it in a projection — but the grant is needed for the WHERE clause.
--
-- Safe to re-run.
-- =============================================================================

set search_path = public, extensions;

grant select (search_vector) on public.properties to anon, authenticated;
