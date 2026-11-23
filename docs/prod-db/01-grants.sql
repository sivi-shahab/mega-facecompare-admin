-- Dijalankan DBA (superuser) di DB "compreface" (dibuat lewat docs/PROD-NEW-DATABASE.md). Hanya memastikan hak akses.
-- psql -h 10.102.47.46 -U postgres -d compreface -f 01-grants.sql
-- Ganti <USER_APLIKASI> dengan user yang dipakai admin dan api.
GRANT CONNECT ON DATABASE compreface TO <USER_APLIKASI>;
GRANT USAGE, CREATE ON SCHEMA dashboard TO <USER_APLIKASI>;
-- Hanya perlu untuk Opsi A (Liquibase menjalankan CREATE EXTENSION IF NOT EXISTS "uuid-ossp"):
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
