-- Dijalankan DBA (superuser) di DB "da". DB "da" dan schema "dashboard" sudah ada; ini hanya memastikan hak akses.
-- psql -h 10.102.47.46 -U postgres -d da -f 01-grants.sql
-- Ganti <USER_APLIKASI> dengan user yang dipakai admin dan api.
GRANT CONNECT ON DATABASE da TO <USER_APLIKASI>;
GRANT USAGE, CREATE ON SCHEMA dashboard TO <USER_APLIKASI>;
-- Hanya perlu untuk Opsi A (Liquibase menjalankan CREATE EXTENSION IF NOT EXISTS "uuid-ossp"):
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
