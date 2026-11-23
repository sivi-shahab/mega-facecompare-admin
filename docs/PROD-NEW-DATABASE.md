# PROD — Membuat database baru `compreface` (step by step)

Panduan membuat DB baru `compreface` di server prod `10.102.47.46:5432`, schema `dashboard`, lalu menyambungkan admin dan api. Tanpa nilai rahasia: password dan signing key dibuat sendiri dan disimpan di vault / Secret Kubernetes.

Terkait: [DEPLOY-PROD.md](../DEPLOY-PROD.md), [TROUBLESHOOT-LIQUIBASE-APP-EXISTS.md](TROUBLESHOOT-LIQUIBASE-APP-EXISTS.md).

## 1. Buat role, database, schema, ekstensi (DBA, superuser)

Script siap pakai: [`prod-db/00-create-database.sql`](prod-db/00-create-database.sql). Ganti `<PASSWORD_DB>` di salinan lokal, lalu:

```bash
psql -h 10.102.47.46 -U postgres -d postgres -f docs/prod-db/00-create-database.sql
```

Isinya:

```sql
CREATE ROLE facecompare_app LOGIN PASSWORD '<PASSWORD_DB>';   -- lewati bila user sudah ada
CREATE DATABASE compreface OWNER facecompare_app ENCODING 'UTF8';
REVOKE ALL ON DATABASE compreface FROM PUBLIC;
GRANT CONNECT ON DATABASE compreface TO facecompare_app;

\c compreface
CREATE SCHEMA dashboard AUTHORIZATION facecompare_app;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;   -- wajib untuk Liquibase
GRANT USAGE ON SCHEMA public TO facecompare_app;
```

## 2. Jaringan dan `pg_hba.conf`

Tambahkan baris untuk DB baru (CIDR node cluster prod), lalu reload:

```
host  compreface  facecompare_app  <CIDR_NODE_CLUSTER>  scram-sha-256
```
```sql
SELECT pg_reload_conf();
```

`k8s/base/networkpolicy.yaml` tidak perlu diubah (server dan port sama).

## 3. Tes koneksi (dari mesin yang punya akses jaringan)

```bash
psql "host=10.102.47.46 port=5432 dbname=compreface user=facecompare_app" \
  -c "select has_schema_privilege(current_user,'dashboard','USAGE, CREATE'),
             (select count(*) from pg_extension where extname='uuid-ossp');"
# hasil: t | 1
```

## 4. Konfigurasi repo (admin dan api)

Di `k8s/base/configmap.env` **kedua repo** (admin sudah diubah di repo ini):

```
POSTGRES_URL=jdbc:postgresql://10.102.47.46:5432/compreface?currentSchema=dashboard,public
DB_SCHEMA=dashboard
SPRING_PROFILES_ACTIVE=prod
```

`DB_SCHEMA` dan `currentSchema` harus sama. Ganti juga `FRS_CRUD_HOST=https://GANTI-HOST-PROD` ke host prod. Ubah repo **api** dengan nilai yang sama persis.

## 5. Secret di cluster

```bash
kubectl create namespace compreface   # bila belum ada

kubectl -n compreface create secret generic compreface-postgres-credentials \
  --from-literal=POSTGRES_USER=facecompare_app \
  --from-literal=POSTGRES_PASSWORD='<PASSWORD_DB>'

kubectl -n compreface create secret generic compreface-admin-secrets \
  --from-literal=SECURITY_SIGNINGKEY="$(openssl rand -hex 32)" \
  --from-literal=EMAIL_USERNAME= \
  --from-literal=EMAIL_PASSWORD=
```

Bila Secret sudah ada dengan password lama, perbarui (`kubectl delete secret` lalu buat ulang) atau pastikan isinya cocok dengan role di langkah 1.

## 6. Build image dan deploy admin

Image harus dibuild dari commit yang memuat `DB_SCHEMA` (`e618f5d` atau lebih baru).

```bash
./scripts/build.sh && ./scripts/push.sh
# isi newTag / digest di k8s/overlays/prod/kustomization.yaml

kubectl kustomize k8s/overlays/prod | grep -E "POSTGRES_URL|SPRING_PROFILES|DB_SCHEMA|image:"
kubectl apply -k k8s/overlays/prod

# migrasi pertama: 1 replica agar Liquibase tidak berjalan paralel
kubectl -n compreface scale deploy/compreface-admin --replicas=1
kubectl -n compreface logs deploy/compreface-admin -f | grep -E "profile|liquibase|Started|ERROR"
```

Log yang benar:

```
The following 1 profile is active: "prod"
Reading from dashboard.databasechangelog
Started FrsApplication
```

Bila log memperlihatkan `"dev"` atau `public.`, hentikan dan lihat [TROUBLESHOOT-LIQUIBASE-APP-EXISTS.md](TROUBLESHOOT-LIQUIBASE-APP-EXISTS.md).

## 7. Verifikasi database

```sql
SELECT count(*) FROM dashboard.databasechangelog;                                  -- 46
SELECT count(*) FROM information_schema.tables WHERE table_schema='dashboard';     -- 16
SELECT count(*) FROM information_schema.tables
 WHERE table_schema='public' AND table_name IN ('app','user','model');             -- 0
```

## 8. Naikkan replica dan deploy api

```bash
kubectl -n compreface scale deploy/compreface-admin --replicas=2
```

Lalu deploy **api** dengan `POSTGRES_URL` dan `DB_SCHEMA` yang sama. Hanya admin yang membuat tabel, jadi api menyusul setelah admin sukses start.

## Catatan

- Data di DB lama (`da`) tidak ikut pindah. Bila perlu, gunakan `pg_dump -n dashboard` lalu restore ke `compreface`.
- Untuk memakai schema `public` saja: hapus `DB_SCHEMA`, ubah `currentSchema=public`, dan lewati `CREATE SCHEMA dashboard`.
- Backup terjadwal dan terenkripsi harus mencakup DB `compreface`.
