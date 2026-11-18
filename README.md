# mega-facecompare-admin

| Metadata | |
|---|---|
| Judul | README mega-facecompare-admin (compreface-admin) |
| Versi | 2.0.0 |
| Tanggal | 2026-10-01 |
| Owner | Tim Platform / DevOps |
| Status | Review |

| Versi | Tanggal | Penulis | Perubahan |
|---|---|---|---|
| 1.0.0 | 2026-09-29 | Claude Code | Versi awal (di monorepo `services/<service>/README.md`) |
| 2.0.0 | 2026-10-01 | Claude Code | Repo mandiri hasil split monorepo Mega-CompreFace |

**Backend administrasi (Spring Boot)** — image `mega/compreface-admin`. Bagian dari CompreFace (fork Exadel CompreFace 1.2.0, Apache 2.0) yang dipecah
dari monorepo Mega-CompreFace menjadi 6 repo. Integrasi full-stack, monitoring, dokumentasi SDLC (SPEC,
ARCHITECTURE, RUNBOOK, SECURITY, TEST_PLAN) dan versi rilis bersama ada di
[mega-facecompare-deploy](https://scm.bankmegadev.com/cobs/data-management/application/mega-facecompare-deploy).

## Fungsi
Backend administrasi (modul Maven `java/admin` + `java/common`): user & role, aplikasi, face collection (model + API key), OAuth2 login (token di DB, cookie `CFSESSION`). **Menjalankan migrasi skema Liquibase** saat start, sehingga harus sukses sebelum api dipakai pada DB kosong.

Source aplikasi: `java/pom.xml` (parent `frs-java`, modul `common` + `admin`), `java/admin/`, `java/common/` (vendored — lihat [java/common/README.md](java/common/README.md)). **Logika aplikasi upstream tidak diubah** di repo ini; perubahan hanya pada
build, konfigurasi, dan dokumentasi.

## Isi repo
| File | Isi |
|---|---|
| `Dockerfile` | Stage 1 `maven:3.8.2-eclipse-temurin-17` (`mvn -pl admin -am package`); stage 2 `eclipse-temurin:17.0.8_7-jre-focal`, uid 1001. **Tanpa** `APPERY_API_KEY` |
| `.dockerignore` | Context: `java/pom.xml`, `java/common`, `java/admin`, `LICENSE`, `NOTICE` |
| `java/common/.checksum` | Checksum isi `java/common` — harus sama dengan repo `mega-facecompare-api` |
| `scripts/build.sh` | Build `mega/compreface-admin:<versi>` dari root repo (versi default: file `VERSION`); tulis `build/images.txt` |
| `scripts/push.sh` | Push ke registry (catat digest ke `build/digests.txt`) atau `--save <dir>` → tarball + `SHA256SUMS` untuk transfer air-gapped |
| `k8s/base/` | Manifest service ini saja (Deployment/StatefulSet, Service, ConfigMap, NetworkPolicy) |
| `k8s/overlays/{dev,prod}/` | Overlay per environment untuk service ini |
| `.gitlab-ci.yml` | validate → build → scan (Trivy) → push; registry & kredensial dari variabel CI |
| `.env.example` | Env var service ini (tanpa nilai rahasia) |

## Port & healthcheck
| Port | Healthcheck | Catatan |
|---|---|---|
| 8080 | – | Aplikasi (`/admin/**`) |
| 8081 | `/actuator/health/liveness`, `/actuator/health/readiness` | Actuator (mail health dimatikan) |

## Env var
Non-rahasia (ConfigMap `compreface-admin`, default juga di-bake di `Dockerfile`/`.env.example`):

| Variabel | Default | Catatan |
|---|---|---|
| `POSTGRES_URL` | `jdbc:postgresql://10.102.47.46:5432/da?currentSchema=dashboard,public` | JDBC URL |
| `DB_SCHEMA` | `public` (k8s: `dashboard`) | schema tabel (Hibernate + Liquibase); harus sama dengan `currentSchema` di `POSTGRES_URL` |
| `PYTHON_URL` | `http://compreface-core:3000` | URL core |
| `SPRING_PROFILES_ACTIVE` | `dev` | profil upstream |
| `ADMIN_JAVA_OPTS` | `-XX:MaxRAMPercentage=75.0` |  |
| `JAVA_TOOL_OPTIONS` | `-Duser.timezone=Asia/Jakarta` |  |
| `MAX_FILE_SIZE` | `5MB` |  |
| `MAX_REQUEST_SIZE` | `10MB` |  |
| `SAVE_IMAGES_TO_DB` | `true` |  |
| `ENABLE_EMAIL_SERVER` | `false` |  |
| `EMAIL_HOST` | `smtp.example.internal` |  |
| `EMAIL_FROM` | `CompreFace <no-reply@example.internal>` |  |
| `FRS_CRUD_HOST` | `http://localhost:8000` | URL publik UI (link email) |
| `MANAGEMENT_SERVER_PORT` | `8081` |  |
| `MANAGEMENT_HEALTH_MAIL_ENABLED` | `false` |  |
| `MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED` | `true` |  |
| `LOGGING_LEVEL_COM_EXADEL` | `INFO` |  |
| `TZ` | `Asia/Jakarta` |  |

Rahasia (Secret Kubernetes — contoh struktur: [k8s/secret.example.yaml](k8s/secret.example.yaml)):

| Variabel | Sumber | Catatan |
|---|---|---|
| `POSTGRES_USER` | Secret `compreface-postgres-credentials` | **wajib** dari Secret / env, tidak pernah di image atau git |
| `POSTGRES_PASSWORD` | Secret `compreface-postgres-credentials` | **wajib** dari Secret / env, tidak pernah di image atau git |
| `SECURITY_SIGNINGKEY` | Secret `compreface-admin-secrets` | **wajib** dari Secret / env, tidak pernah di image atau git |
| `EMAIL_USERNAME` | Secret `compreface-admin-secrets` (opsional) | **wajib** dari Secret / env, tidak pernah di image atau git |
| `EMAIL_PASSWORD` | Secret `compreface-admin-secrets` (opsional) | **wajib** dari Secret / env, tidak pernah di image atau git |

Referensi lengkap seluruh service: `docs/CONFIGURATION.md` di repo deploy.

## Build
```bash
scripts/build.sh                       # → mega/compreface-admin:$(cat VERSION)
REGISTRY=registry.example.internal scripts/build.sh && scripts/push.sh
scripts/push.sh --save /media/transfer # air-gapped: docker save + SHA256SUMS → docker load di sisi internal
# manual (build context = root repo, tanpa akses ke repo lain):
docker build -t mega/compreface-admin:1.2.0 .
```
Tag `latest` ditolak. Versi image dinaikkan dengan mengubah `VERSION` + `CHANGELOG.md`; versi yang dirilis
bersama dicatat di `versions.env` repo deploy.

## Run (lokal, tanpa orkestrasi)
```bash
cp .env.example .env    # isi nilai yang ditandai WAJIB
docker run -d --name compreface-admin --read-only --tmpfs /tmp \
  --env-file .env --network <network-yang-berisi-db-core> mega/compreface-admin:1.2.0
docker exec compreface-admin curl -fsS http://127.0.0.1:8081/actuator/health/readiness
```
Untuk full-stack (5 service) gunakan `scripts/compose.sh` di repo deploy.

## Kubernetes
```bash
kubectl kustomize k8s/overlays/dev          # render
kubectl apply -k k8s/overlays/dev           # namespace compreface-dev harus sudah ada (dibuat repo deploy)
```
Namespace, NetworkPolicy default-deny + DNS egress, dan Secret dikelola di repo deploy. Repo deploy menyimpan
salinan `k8s/base/` repo ini di `k8s/services/compreface-admin/` — setelah mengubah `k8s/base/`, jalankan
`scripts/sync-manifests.sh` di repo deploy.

## Kontrak ke service lain
Nama Service, port dan nama env var **tidak berubah** dibanding monorepo — perubahannya adalah breaking change
dan harus dikoordinasikan lewat repo deploy.

- **Dipanggil oleh**: `compreface-fe` (`/admin/**` → `compreface-admin:8080`).
- **Memanggil**: PostgreSQL eksternal `10.102.47.46:5432` (JDBC, DB `da`, schema `dashboard`), `compreface-core:3000` (`PYTHON_URL`, status/plugin).
- **Skema DB**: admin pemilik migrasi Liquibase (`java/admin/src/main/resources/db/changelog`). api memakai skema yang sama → rilis yang mengubah skema harus men-deploy admin lebih dulu.
- Secret `compreface-postgres-credentials` dipakai bersama dengan api & db; `compreface-admin-secrets` khusus admin (contoh: [k8s/secret.example.yaml](k8s/secret.example.yaml)).

## Catatan operasional
Startup ± 30–40 s (lebih lama pada migrasi pertama). Butuh `/tmp` writable.

## Lisensi
Apache License 2.0 — lihat [LICENSE](LICENSE) dan [NOTICE](NOTICE) (atribusi Exadel, Inc. dipertahankan).
