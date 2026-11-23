# Troubleshooting PROD — admin CrashLoop: `relation "app" already exists` (Liquibase)

Pod `compreface-admin` gagal start dengan error:

```
Migration failed for change set db/changelog/db.changelog-0.0.3.yaml::create-app-table::Andrei Hayeuski:
Reason: ... ERROR: relation "app" already exists
[Failed SQL: (0) CREATE TABLE public.app (...)]
```

## 1. Diagnosis (dari log)

Dua baris di log menunjukkan konfigurasi prod **tidak terpakai**:

| Baris log | Seharusnya (prod) | Artinya |
|---|---|---|
| `The following 1 profile is active: "dev"` | `prod` | ConfigMap `compreface-admin` tidak ter-load; yang aktif default `ENV SPRING_PROFILES_ACTIVE=dev` dari Dockerfile |
| `Reading from public.databasechangelog` dan `CREATE TABLE public.app` | `dashboard.databasechangelog`, `dashboard.app` | `DB_SCHEMA` tidak terbaca atau image dibuild dari kode lama (sebelum commit `e618f5d`), sehingga Liquibase bekerja di schema `public` |

Akibatnya:

1. Liquibase menjalankan changeset 0.0.1 dan 0.0.2 di `public`. Kedua tabel (`user`, `organization`) **terbuat di `public`**, bukan di `dashboard`.
2. Di changeset 0.0.3 tabel `public.app` sudah ada (sisa percobaan sebelumnya, atau tabel lain di `public`), lalu gagal.

Akar masalah: **admin menulis ke schema yang salah**. Jangan langsung menghapus tabel `app`. Perbaiki konfigurasi dulu (langkah 2 sampai 4), baru bereskan `public` (langkah 5).

## 2. Hentikan crash loop

```bash
kubectl -n compreface scale deploy/compreface-admin --replicas=0
```

Overlay prod memakai 2 replica. Untuk migrasi, jalankan **1 replica** agar Liquibase tidak berjalan paralel (lihat langkah 6).

## 3. Cek konfigurasi yang benar-benar dipakai

```bash
# a. ConfigMap di cluster
kubectl -n compreface get cm -l app.kubernetes.io/name=compreface-admin
kubectl -n compreface get cm compreface-admin -o yaml | grep -E "SPRING_PROFILES|POSTGRES_URL|DB_SCHEMA"

# b. Env yang dipakai Deployment (envFrom harus ada configMapRef)
kubectl -n compreface get deploy compreface-admin -o jsonpath='{.spec.template.spec.containers[0].envFrom}{"\n"}'

# c. Image yang dipakai
kubectl -n compreface get deploy compreface-admin -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Nilai yang diharapkan di ConfigMap:

```
SPRING_PROFILES_ACTIVE=prod
POSTGRES_URL=jdbc:postgresql://10.102.47.46:5432/compreface?currentSchema=dashboard,public
DB_SCHEMA=dashboard
```

Bila ConfigMap tidak ada, atau isinya lama (profile `dev`, tanpa `DB_SCHEMA`), manifest prod belum di-apply. Lanjut ke langkah 4.

Cek juga image. Image harus dibuild dari commit yang memuat `DB_SCHEMA` (`e618f5d` atau lebih baru). Cara cepat: bila tag lama (sebelum fix) masih dipakai, build ulang.

```bash
# di repo admin
git log --oneline | grep -E "e618f5d|DB_SCHEMA"     # commit harus ada di branch yang dibuild
grep -n "DB_SCHEMA" java/admin/src/main/resources/application.yml   # harus ada 3 baris
```

## 4. Perbaiki manifest dan image

1. Pastikan deploy memakai **overlay prod**, bukan base atau dev:
   ```bash
   kubectl kustomize k8s/overlays/prod | grep -E "POSTGRES_URL|SPRING_PROFILES|DB_SCHEMA|image:"
   ```
   Output harus berisi `SPRING_PROFILES_ACTIVE=prod`, `DB_SCHEMA=dashboard`, dan `currentSchema=dashboard,public`.
2. Bila image lama, build dan push ulang dari commit terbaru, lalu isi `newTag` (atau digest) di `k8s/overlays/prod/kustomization.yaml`:
   ```bash
   ./scripts/build.sh && ./scripts/push.sh
   ```
3. Ganti `FRS_CRUD_HOST=https://GANTI-HOST-PROD` di `k8s/base/configmap.env` bila belum.
4. Apply (belum menyalakan pod, replica masih 0 bila memakai `scale` manual; bila overlay mengembalikan 2, scale ulang ke 0 setelah apply):
   ```bash
   kubectl apply -k k8s/overlays/prod
   kubectl -n compreface scale deploy/compreface-admin --replicas=0
   ```

> Catatan: ConfigMap dibuat dengan `configMapGenerator`, jadi nama berakhiran hash dan perubahan isi memicu rollout. Pastikan Deployment menunjuk nama ConfigMap yang baru.

## 5. Periksa dan bereskan database

Jalankan sebagai user aplikasi (atau DBA) di DB `compreface`:

```bash
psql "host=10.102.47.46 port=5432 dbname=compreface user=<USER_APLIKASI>"
```

### 5.1 Lihat apa yang ada di tiap schema

```sql
-- tabel di public dan dashboard
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('public','dashboard')
ORDER BY table_schema, table_name;

-- riwayat Liquibase di masing-masing schema (abaikan error bila tabelnya belum ada)
SELECT id, filename, dateexecuted FROM public.databasechangelog   ORDER BY orderexecuted;
SELECT id, filename, dateexecuted FROM dashboard.databasechangelog ORDER BY orderexecuted;

-- kepemilikan lock Liquibase (harus kosong / FALSE)
SELECT * FROM public.databasechangeloglock;
SELECT * FROM dashboard.databasechangeloglock;
```

Tentukan kondisinya:

| Kondisi | Tindakan |
|---|---|
| `dashboard` **kosong**; `public` berisi tabel aplikasi (`app`, `user`, `organization`, dst.) hasil percobaan gagal | Skenario A |
| `dashboard` sudah berisi tabel tetapi `dashboard.databasechangelog` **kosong** (DDL dijalankan tanpa data awal) | Skenario B |
| `dashboard` lengkap (16 tabel, `databasechangelog` terisi 46 changeset) | Tidak perlu migrasi. Cukup perbaiki konfigurasi (langkah 3 dan 4) lalu start admin |

### Skenario A: `dashboard` kosong, sisa tabel ada di `public`

**Backup dulu**, lalu pastikan tabel-tabel di `public` memang hanya milik FaceCompare (tanyakan DBA bila DB `compreface` dipakai aplikasi lain):

```bash
pg_dump -h 10.102.47.46 -U <USER_APLIKASI> -d compreface -n public -Fc -f public-backup-$(date +%F).dump
```

Hapus **hanya** objek yang dibuat Liquibase pada percobaan gagal tadi (daftar dari query 5.1; jangan `DROP SCHEMA public`):

```sql
BEGIN;
DROP TABLE IF EXISTS public.app, public."user", public.organization,
                     public.databasechangelog, public.databasechangeloglock CASCADE;
DROP SEQUENCE IF EXISTS public.user_id_seq, public.organization_id_seq, public.app_id_seq;
-- tambahkan tabel/sequence FaceCompare lain yang muncul di query 5.1
COMMIT;
```

Periksa ulang query 5.1: `public` tidak boleh lagi berisi tabel FaceCompare.

### Skenario B: DDL manual sudah dijalankan, data awal belum

Jalankan data awal agar `dashboard.databasechangelog` terisi (lihat [DEPLOY-PROD.md](../DEPLOY-PROD.md) bagian 4, Opsi B):

```bash
psql "host=10.102.47.46 port=5432 dbname=compreface user=<USER_APLIKASI>" -f docs/prod-db/02b-seed-data.sql
```

Bila 02b gagal karena data sebagian sudah ada, kosongkan schema `dashboard` (setelah backup dan konfirmasi DBA), lalu ulangi dari Skenario A (Opsi A: biarkan Liquibase membuat semuanya).

### 5.2 Prasyarat Opsi A (Liquibase)

```sql
SELECT has_schema_privilege(current_user, 'dashboard', 'USAGE, CREATE');   -- harus t
SELECT extname FROM pg_extension WHERE extname = 'uuid-ossp';              -- harus ada 1 baris
```

Bila ekstensi belum ada, minta DBA (superuser): `CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;`

### 5.3 Lock Liquibase tersangkut

Bila `databasechangeloglock.locked = true` setelah pod crash (log berisi "Waiting for changelog lock"):

```sql
UPDATE dashboard.databasechangeloglock SET locked = FALSE, lockgranted = NULL, lockedby = NULL WHERE id = 1;
```

Lakukan hanya bila tidak ada pod admin yang sedang berjalan (replica 0).

## 6. Start admin dan verifikasi

```bash
# 1 replica dulu agar migrasi tidak paralel
kubectl -n compreface scale deploy/compreface-admin --replicas=1
kubectl -n compreface logs deploy/compreface-admin -f | grep -E "profile|liquibase|Started|ERROR"
```

Log yang benar:

```
The following 1 profile is active: "prod"
liquibase.changelog : Reading from dashboard.databasechangelog
... ChangeSet ... ran successfully
Started FrsApplication
```

Tidak boleh ada lagi `public.` pada baris Liquibase. Lalu verifikasi di DB:

```sql
SELECT count(*) FROM dashboard.databasechangelog;      -- 46
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'dashboard';   -- 16
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('app','user','organization','model');   -- 0
```

Bila semua benar, naikkan ke replica sesuai overlay:

```bash
kubectl -n compreface scale deploy/compreface-admin --replicas=2
kubectl -n compreface get pods -l app.kubernetes.io/name=compreface-admin
```

## 7. Ringkasan cepat

1. `scale --replicas=0`.
2. Cek profile dan `DB_SCHEMA` di pod. Bila `dev` atau kosong, apply overlay prod dan build ulang image dari commit terbaru.
3. Backup lalu bersihkan sisa tabel FaceCompare di `public` (jangan drop schema).
4. Pastikan `dashboard` kosong atau lengkap (jangan setengah), hak akses dan `uuid-ossp` OK.
5. Start 1 replica, tunggu `Started FrsApplication`, verifikasi 46 changeset, lalu scale ke 2.

## 8. Pencegahan

- Jangan memakai `kubectl apply -f` manual pada base; selalu `kubectl apply -k k8s/overlays/prod`.
- Pin image dengan digest dan pastikan build memuat `DB_SCHEMA`.
- Selalu cek baris `profile is active: "prod"` dan `Reading from dashboard.databasechangelog` pada deploy pertama.
