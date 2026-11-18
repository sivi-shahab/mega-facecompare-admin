-- Jalankan sebagai superuser postgres di server 10.102.47.46
-- psql -h 10.102.47.46 -U postgres -f 01-create-db.sql
CREATE ROLE facecompare_app WITH LOGIN PASSWORD '<PASSWORD_DB>';
CREATE DATABASE dashboard OWNER facecompare_app ENCODING 'UTF8' TEMPLATE template0;
\c dashboard
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
GRANT ALL ON SCHEMA public TO facecompare_app;
ALTER SCHEMA public OWNER TO facecompare_app;
REVOKE CONNECT ON DATABASE dashboard FROM PUBLIC;
GRANT CONNECT ON DATABASE dashboard TO facecompare_app;
