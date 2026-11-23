# Deploy PROD — FaceCompare (database `compreface`, schema `dashboard`)

Panduan menaikkan FaceCompare ke produksi: menyiapkan akses database, membuat tabel, mengatur konfigurasi, dan deploy.
Dokumen ini **tanpa nilai rahasia**. Password dan signing key dibuat sendiri dan disimpan di vault / Secret Kubernetes, bukan di git.

| Item | Nilai |
|---|---|
| Server PostgreSQL prod | `10.102.47.46:5432` (di luar cluster, dikelola DBA) |
| Database | `compreface` (dibuat DBA, lihat [`docs/PROD-NEW-DATABASE.md`](docs/PROD-NEW-DATABASE.md)) |
| Schema | `dashboard` (sudah ada); **semua tabel dibuat di schema ini, bukan `public`** |
| Namespace Kubernetes | `compreface` |
| Script SQL | [`docs/prod-db/`](docs/prod-db) |

## 1. Arsitektur singkat

```
Ingress (TLS) -> fe (nginx) -> admin :8080 --\
                            -> api   :8080 ---+--> PostgreSQL 10.102.47.46 / compreface / schema dashboard
                       admin, api -> core :3000 (GPU)
```

- Hanya **admin** dan **api** yang mengakses database. Hanya **admin** yang membuat tabel (Liquibase); api tidak membuat tabel.
- Schema dipilih lewat dua pengaturan yang harus sama: `DB_SCHEMA=dashboard` dan `?currentSchema=dashboard,public` pada `POSTGRES_URL` (bagian 5).
- Repo yang dideploy: `mega-facecompare-fe`, `-admin`, `-api`, `-core`. Repo `-db` hanya dipakai bila PostgreSQL dijalankan di dalam cluster (tidak untuk prod ini).

> **Wajib pakai versi kode terbaru.** Versi lama menulis `public` permanen di entity JPA dan changelog Liquibase, sehingga tidak bisa memakai schema `dashboard`. Pastikan image admin dan api dibuild dari commit yang memuat `DB_SCHEMA`.

## 2. Prasyarat

- PostgreSQL 11 atau lebih baru di `10.102.47.46`, port 5432 dibuka dari node cluster prod (`pg_hba.conf`, metode `scram-sha-256`).
- Database `compreface` dan schema `dashboard` sudah ada, dan user aplikasi punya hak `CONNECT` pada DB serta `USAGE, CREATE` pada schema (lihat bagian 3).
- Cluster Kubernetes dengan namespace `compreface`, `kubectl` dan kustomize.
- Node GPU untuk core (NVIDIA device plugin, VRAM minimal 10 GB).
- Image `mega/compreface-{admin,api,core,fe}` sudah ada di registry internal.
- Sertifikat TLS dari PKI internal untuk Ingress (data biometrik, UU PDP).

## 3. Akses database

DB dan schema sudah ada, jadi cukup pastikan hak akses user aplikasi. Jalankan sebagai superuser (ganti `<USER_APLIKASI>` di salinan lokal [`01-grants.sql`](docs/prod-db/01-grants.sql)):

```bash
psql -h 10.102.47.46 -U postgres -d compreface -f docs/prod-db/01-grants.sql
```

Cek dari mesin yang punya akses jaringan:

```bash
psql "host=10.102.47.46 port=5432 dbname=compreface user=<USER_APLIKASI>" \
  -c "select has_schema_privilege(current_user, 'dashboard', 'USAGE, CREATE');"   # t
```

## 4. Membuat tabel (di `compreface`, schema `dashboard`)

Skema: 16 tabel (`app`, `databasechangelog`, `databasechangeloglock`, `embedding`, `img`, `install_info`, `model`, `model_statistic`, `oauth_access_token`, `oauth_client_details`, `oauth_refresh_token`, `reset_password_token`, `subject`, `table_lock`, `user`, `user_app_role`) dan 5 sequence, semuanya bernama `dashboard.<nama>`. Pilih salah satu opsi.

### Opsi A (disarankan): admin membuat tabel otomatis

Admin menjalankan 46 changeset Liquibase pada start pertama, langsung ke schema `dashboard`. Opsi ini butuh ekstensi `uuid-ossp` di DB `compreface` (satu changeset memanggil `uuid_generate_v1()`); minta DBA menjalankan `CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;` bila belum ada.

1. Selesaikan bagian 3 dan 5.
2. Deploy **admin dengan 1 replica** lebih dulu agar migrasi tidak berjalan paralel.
3. Tunggu log `Started FrsApplication`:
   ```bash
   kubectl -n compreface logs deploy/compreface-admin -f | grep -E "liquibase|Started|ERROR"
   ```
4. Verifikasi (bagian 4.1), lalu naikkan admin ke 2 replica.

### Opsi B: lewat DBeaver (manual)

Pakai bila DBA ingin menjalankan DDL sendiri. **DDL dan data awal harus dijalankan keduanya.** Tanpa data awal, `dashboard.databasechangelog` kosong dan admin akan mencoba membuat tabel lagi lalu gagal "already exists". Jalankan hanya ke schema `dashboard` yang **kosong**. Opsi ini tidak butuh superuser maupun ekstensi.

1. DBeaver > New Database Connection > PostgreSQL: host `10.102.47.46`, port `5432`, database `compreface`, user aplikasi. Aktifkan Auto-commit.
2. Buka [`02a-ddl-only.sql`](docs/prod-db/02a-ddl-only.sql) dan jalankan dengan **Execute SQL Script (Alt+X)**: membuat 16 tabel, 5 sequence, semua primary key, unique, dan foreign key di schema `dashboard`.
3. Buka [`02b-seed-data.sql`](docs/prod-db/02b-seed-data.sql) dan jalankan dengan Alt+X: data demo, client OAuth, 46 changeset Liquibase, dan nilai sequence. Urutan insert sudah benar.
4. Verifikasi (bagian 4.1).

Bila gagal di tengah, hapus isinya lalu ulangi dari langkah 2: `DROP SCHEMA dashboard CASCADE; CREATE SCHEMA dashboard;` (jalankan hanya bila schema memang baru dan kosong sebelumnya), kemudian beri ulang hak bagian 3.

### Opsi C: psql

```bash
export PGPASSWORD='<PASSWORD_DB>'   # jangan simpan di history/script
psql -h 10.102.47.46 -U <USER_APLIKASI> -d compreface -v ON_ERROR_STOP=1 -f docs/prod-db/02a-ddl-only.sql
psql -h 10.102.47.46 -U <USER_APLIKASI> -d compreface -v ON_ERROR_STOP=1 -f docs/prod-db/02b-seed-data.sql
```

### 4.1 Verifikasi tabel

```sql
SELECT count(*) FROM pg_tables WHERE schemaname = 'dashboard';   -- 16
SELECT count(*) FROM dashboard.databasechangelog;                -- 46
SELECT client_id FROM dashboard.oauth_client_details;            -- CommonClientId
SELECT count(*) FROM pg_tables WHERE schemaname = 'public' AND tablename IN ('user','app','model');  -- 0 (tidak ada tabel di public)
```

> **Akun demo.** Skema membawa user demo `demo@demo.com`. User pertama yang mendaftar di UI mengambil alih akun ini dan menjadi Owner. Daftarkan akun Owner resmi segera setelah deploy, sebelum URL prod dibuka ke pengguna.

## 5. Konfigurasi

### 5.1 Nilai di repo (sudah diubah ke prod)

| Repo | File | Nilai |
|---|---|---|
| admin, api | `k8s/base/configmap.env` | `POSTGRES_URL=jdbc:postgresql://10.102.47.46:5432/compreface?currentSchema=dashboard,public`, `DB_SCHEMA=dashboard`, `SPRING_PROFILES_ACTIVE=prod` |
| admin, api | `k8s/base/networkpolicy.yaml` | egress DB `10.102.47.46/32` port 5432 |
| admin | `k8s/base/configmap.env` | `FRS_CRUD_HOST=https://GANTI-HOST-PROD` (**wajib diganti** ke host prod) |

Ganti juga `registry.example.internal` di `k8s/overlays/prod/kustomization.yaml` tiap repo, dan sebaiknya pin image dengan digest.

### 5.2 Secret (dibuat sekali di cluster, tidak masuk git)

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

`SECURITY_SIGNINGKEY` harus berbeda dari dev dan tidak boleh berubah setelah go-live (token login lama jadi tidak valid). Bila bank memakai Vault / Sealed Secrets / External Secrets, buat Secret dengan nama dan key yang sama.

### 5.3 Parameter penting

| Service | Variabel | Nilai prod |
|---|---|---|
| admin, api | `POSTGRES_URL` | `jdbc:postgresql://10.102.47.46:5432/compreface?currentSchema=dashboard,public` |
| admin, api | `DB_SCHEMA` | `dashboard` (harus sama dengan `currentSchema`) |
| admin, api | `POSTGRES_USER` / `POSTGRES_PASSWORD` | dari Secret `compreface-postgres-credentials` |
| admin, api | `SPRING_PROFILES_ACTIVE` | `prod` |
| admin | `SECURITY_SIGNINGKEY` | dari Secret `compreface-admin-secrets` |
| admin | `FRS_CRUD_HOST` | `https://<host-prod>` |
| admin, api | `PYTHON_URL` | `http://compreface-core:3000` |
| admin, api | `SAVE_IMAGES_TO_DB` | `true` (gambar wajah disimpan di tabel `img`) |
| admin, api, fe | `MAX_FILE_SIZE` / `MAX_REQUEST_SIZE` / `CLIENT_MAX_BODY_SIZE` | `5MB` / `10MB` / `10M` |
| core | `UWSGI_PROCESSES` | `4` (overlay prod, 1 GPU 24 GB) |

### 5.4 Ingress dan TLS

Aktifkan `ingress.example.yaml` di overlay prod fe (ganti host dan `ingressClassName`), lalu:

```bash
kubectl -n compreface create secret tls compreface-tls --cert=<cert.pem> --key=<key.pem>
```

## 6. Urutan deploy

DB, lalu Secret, core, admin (1 replica), api, fe. Admin harus selesai migrasi sebelum api start.

```bash
# Render dan review dulu; pastikan tidak ada 10.14.21.67, "dev", atau registry.example.internal
kubectl kustomize k8s/overlays/prod | grep -E "POSTGRES_URL|SPRING_PROFILES|cidr|image:"

(cd mega-facecompare-core  && kubectl apply -k k8s/overlays/prod)
kubectl -n compreface rollout status deploy/compreface-core --timeout=10m

(cd mega-facecompare-admin && kubectl apply -k k8s/overlays/prod)
kubectl -n compreface scale deploy/compreface-admin --replicas=1
kubectl -n compreface logs deploy/compreface-admin -f      # tunggu "Started FrsApplication"
kubectl -n compreface scale deploy/compreface-admin --replicas=2

(cd mega-facecompare-api   && kubectl apply -k k8s/overlays/prod)
(cd mega-facecompare-fe    && kubectl apply -k k8s/overlays/prod)
```

## 7. Verifikasi pasca deploy

```bash
kubectl -n compreface get pods
kubectl -n compreface exec deploy/compreface-admin -- wget -qO- http://127.0.0.1:8081/actuator/health/readiness
kubectl -n compreface exec deploy/compreface-api   -- wget -qO- http://127.0.0.1:8081/actuator/health/readiness
curl -sk https://<host-prod>/core/status

# Uji face compare dengan x-api-key Verification Service prod
curl -sk -X POST https://<host-prod>/api/v1/verification/verify \
  -H "x-api-key: <api-key-verification>" \
  -F source_image=@wajah1.jpg -F target_image=@wajah2.jpg
```

Lalu daftarkan akun Owner resmi di UI dan buat Application serta Service untuk mendapat `x-api-key` prod.

## 8. Checklist go-live

- [ ] DB `compreface` dan schema `dashboard` ada, user aplikasi punya hak `USAGE, CREATE` pada schema
- [ ] `pg_hba.conf` dan firewall hanya membuka 5432 dari cluster prod
- [ ] Backup terjadwal dan terenkripsi untuk DB `compreface` aktif dan sudah dites restore
- [ ] Secret `compreface-postgres-credentials` dan `compreface-admin-secrets` ada di namespace `compreface`
- [ ] `FRS_CRUD_HOST` dan registry sudah diganti dari placeholder
- [ ] Image dari registry internal, di-pin digest, hasil scan Trivy tanpa temuan CRITICAL
- [ ] 16 tabel di schema `dashboard` dan 46 baris `databasechangelog` terverifikasi
- [ ] Ingress dengan TLS PKI internal aktif
- [ ] Akun Owner resmi terdaftar (akun demo diambil alih)
- [ ] Uji verifikasi wajah end-to-end berhasil

## 9. Rollback

- **Aplikasi:** `kubectl -n compreface rollout undo deploy/<service>`, atau apply ulang overlay dengan digest versi sebelumnya.
- **DB pada go-live pertama, migrasi gagal di tengah:** `DROP SCHEMA dashboard CASCADE; CREATE SCHEMA dashboard;` (hanya bila schema memang kosong sebelum deploy), beri ulang hak bagian 3, lalu ulangi bagian 4. Bila `databasechangeloglock.locked = true` setelah pod mati: `UPDATE dashboard.databasechangeloglock SET locked = false, lockgranted = NULL, lockedby = NULL;` sebelum start ulang admin.
- **DB setelah ada data:** jangan drop. Restore dari backup terakhir. Ambil backup (`pg_dump -Fc`) sebelum setiap upgrade versi admin karena versi baru bisa menambah changeset Liquibase.
