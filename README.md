# Aplikasi Sekolah Terpadu — Yayasan Mutiara Islam Cileungsi

Fase 1–4 dari blueprint: data induk, kesiswaan, poin pelanggaran (total otomatis), rekap,
portal siswa (NIS + PIN), hak akses per unit (SD/SMP/SMA), audit log, dan **modul akademik**
(presensi harian, jadwal, nilai berbobot, rapor).

**Teknologi:** SPA tanpa build (HTML/CSS/JS modul) + fungsi serverless Vercel (`api/`) + Supabase (Postgres, Auth, RLS).
Tidak ada dependensi npm, jadi tidak ada langkah `npm install`/build.

## 1. Database (Supabase)
Jalankan berurutan di SQL Editor (atau `supabase db push`) file di `supabase/migrations/`:
`..._init_schema.sql` → `..._functions.sql` → `..._seed.sql` → `..._list_functions.sql` → `..._harden_search_path.sql` → `20261024000005_akademik.sql` (Fase 4).
> Nama unit di seed ("SD/SMP/SMA Mutiara Islam Cileungsi") dan 6 jenis pelanggaran + poinnya hanyalah **contoh**.
> Sesuaikan dengan tata tertib resmi (menu Aturan Poin / Master Data).

## 2. Pengguna pertama (admin yayasan)
1. Supabase → Authentication → Users → *Add user* (email + password, centang auto-confirm).
2. Di SQL Editor (ganti `<UID>` dengan id pengguna tadi):
```sql
insert into public.profiles (id, full_name, email) values ('<UID>', 'Admin Yayasan', 'email@anda');
insert into public.user_roles (user_id, role, school_id) values ('<UID>', 'admin_yayasan', null);
```
Pengguna lain (kepala sekolah, kesiswaan, guru, BK, wali kelas) dibuat dari menu **Pengguna**.

## 3. Deploy ke Vercel
1. Import folder ini sebagai project (Framework: *Other*; tidak ada build command; output sudah diatur di `vercel.json`).
2. Environment Variables (Production):

| Nama | Isi |
|---|---|
| `SUPABASE_URL` | URL project Supabase |
| `SUPABASE_ANON_KEY` | publishable/anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | secret/service_role key (**rahasia**, jangan dibagikan) |
| `SESSION_SECRET` | string acak ≥ 32 karakter |

3. Deploy, lalu di Supabase → Authentication → URL Configuration isi Site URL dengan domain Vercel.

## 4. Alur pemakaian
- Guru/Kesiswaan: **Catat Pelanggaran** → ketik NIS → sistem menampilkan nama & kelas → pilih jenis (poin otomatis).
- Laporan guru berstatus *menunggu* sampai disahkan Kesiswaan; hanya yang disahkan dihitung.
- Koreksi catatan disahkan wajib beralasan; semua perubahan masuk audit log.
- Siswa: `/cek-poin` dengan NIS + PIN. Kesiswaan membuat/reset PIN dari menu Siswa; PIN awal wajib diganti.

## 5. Modul akademik (Fase 4)
Menu baru: **Presensi, Nilai, Jadwal, Rapor, Akademik** (pengaturan). Siswa melihat Jadwal, Kehadiran, dan Rapor terbit di portal `/cek-poin`.
- **Persiapan (kurikulum/admin sekolah)**, menu *Akademik*: cek Mata pelajaran dan KKM, atur *Penugasan guru* per kelas, cek *Komponen nilai* (total bobot harus 100%), dan *Jam pelajaran*. Lalu isi grid di menu *Jadwal*; sistem menolak guru yang mengajar di dua kelas pada jam yang sama.
- **Presensi:** harian per kelas (H/I/S/A/T). Wali kelas mengisi, bisa mengubah sampai 7 hari ke belakang; kesiswaan/admin sampai 366 hari.
- **Nilai:** guru mapel mengisi per penilaian (Tugas, UH, UTS, UAS). Beberapa nilai dalam satu komponen dirata-rata, lalu dibobot. Predikat A ≥ 90, B ≥ 80, C ≥ 70, selain itu D. Tuntas bila nilai akhir ≥ KKM.
- **Rapor:** draf → wali kelas mengisi catatan → kurikulum memvalidasi (nilai terkunci) → diterbitkan (kurikulum/kepala sekolah) dan tampil di portal siswa. Membuka kembali rapor wajib beralasan dan tercatat di audit log.
> Mata pelajaran (9, KKM 75), komponen nilai (20/20/25/35) dan 8 jam pelajaran di migrasi adalah **contoh**; sesuaikan dengan kurikulum sekolah.
> Setelah menerapkan migrasi, **deploy ulang** di Vercel agar `api/siswa/akademik.js` dan tampilan baru aktif.

## 6. Uji
`scripts/test-db.sh` (skenario DB/RLS, butuh Postgres lokal) serta `test/e2e.mjs` dan `test/e2e-akademik.mjs` (browser, memakai mock Supabase; jalankan `scripts/e2e-env.sh` untuk menyiapkan data).

## Belum termasuk
Kenaikan kelas, prestasi, jurnal mengajar, tugas/PR, presensi per jam pelajaran, rapor deskripsi per mapel, alur persetujuan koreksi mundur.
