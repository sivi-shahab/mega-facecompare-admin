-- Dijalankan DBA (superuser) di server prod 10.102.47.46. Membuat DB baru "compreface".
-- Langkah 1 (di DB postgres):  psql -h 10.102.47.46 -U postgres -d postgres -f 00-create-database.sql
-- Ganti <PASSWORD_DB> di SALINAN LOKAL (jangan commit password). Lewati CREATE ROLE bila user sudah ada.
-- Langkah 2 (di DB compreface) ada di bawah; jalankan setelah \c compreface.

CREATE ROLE facecompare_app LOGIN PASSWORD '<PASSWORD_DB>';

CREATE DATABASE compreface OWNER facecompare_app ENCODING 'UTF8';
REVOKE ALL ON DATABASE compreface FROM PUBLIC;
GRANT CONNECT ON DATABASE compreface TO facecompare_app;

\c compreface

CREATE SCHEMA dashboard AUTHORIZATION facecompare_app;

-- Wajib untuk Liquibase (changeset memanggil uuid_generate_v1()).
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
GRANT USAGE ON SCHEMA public TO facecompare_app;
