# Rawat Motor

Aplikasi Flutter untuk menyimpan motor, memantau odometer, dan mengatur jadwal
perawatan berbasis jarak maupun tanggal.

## Menjalankan aplikasi

1. Salin `env/example.json` menjadi `env/dev.json`.
2. Isi `SUPABASE_URL` dan `SUPABASE_ANON_KEY` dengan URL proyek dan public
   anon/publishable key Supabase. Jangan gunakan `service_role` key di aplikasi.
3. Jalankan migrasi SQL di `supabase/migrations/` pada proyek Supabase, sesuai
   urutan nama file. Terapkan juga migration terbaru setiap kali fitur backend
   diperbarui.
4. Jalankan aplikasi:

   ```shell
   flutter run --dart-define-from-file=env/dev.json
   ```

File konfigurasi di `env/*.json` diabaikan Git, kecuali `env/example.json`.
Jangan commit nilai konfigurasi lingkungan.

## Fitur yang sudah tersedia

- Daftar, masuk, dan reset kata sandi melalui Supabase Auth.
- Onboarding dua slide yang hanya tampil pada penggunaan pertama.
- Tambah, edit, hapus, dan pilih motor aktif.
- Pencatatan odometer serta riwayat perubahan odometer.
- Riwayat servis dengan total biaya; catatan dari jadwal memperbarui titik awal jadwal.
- Lampiran maksimal lima foto nota per catatan pada bucket privat Supabase.
- Hapus catatan servis dengan pemulihan titik awal jadwal dan pembersihan lampiran.
- Edit catatan servis dengan pembaruan odometer dan titik awal jadwal terkait.
- Foto motor privat yang dikompres, dengan bucket dan kebijakan akses per akun.
- Pembuatan dan pemantauan jadwal perawatan berdasarkan kilometer atau waktu.
- Edit jadwal, tunda pengingat 1/3/7 hari, dan nonaktifkan jadwal.
- Pengingat lokal Android berdasarkan tanggal dan kilometer, dengan pengaturan
  waktu pengingat dan izin notifikasi.
- Kotak masuk notifikasi yang dikelompokkan berdasarkan hari serta fitur tandai
  sudah dibaca.
- Penawaran pembuatan jadwal standar saat motor baru ditambahkan.
- Profil dasar, status verifikasi email, ubah nama/telepon, bantuan, kebijakan
  privasi, informasi aplikasi, dan keluar dengan konfirmasi.
- Ubah kata sandi dengan verifikasi kata sandi lama dan penghapusan akun melalui
  Supabase Edge Function.
- Cache baca offline untuk motor, jadwal, dan riwayat servis, dengan penanda
  waktu sinkronisasi di Beranda.
- Riwayat servis dapat dicari dan difilter menurut tahun/jenis; catatan dapat
  diedit dan dihapus.
- Monitoring persentase interval dan skor kesehatan motor dari jadwal aktif.
- Row Level Security dan fungsi database untuk operasi yang perlu atomik.

## Pengingat dan penghapusan akun di Supabase

Migration membuat kotak masuk notifikasi dan preferensi pengingat. Untuk membuat
pengingat tanggal/km masuk ke kotak masuk setiap hari, deploy fungsi:

```shell
supabase functions deploy send-maintenance-reminders
supabase secrets set CRON_SECRET="nilai-rahasia-acak"
```

Jadwalkan HTTP `POST` harian ke
`https://<PROJECT_ID>.supabase.co/functions/v1/send-maintenance-reminders`
pada pukul 00:00 UTC (07:00 WIB), dengan header `x-cron-secret` yang sama dan
body `{}`. Fungsi memverifikasi header itu sebelum memakai service role yang
tersedia di Edge Functions. Jangan simpan service role key di aplikasi.

Untuk mengaktifkan penghapusan akun, deploy juga fungsi:

```shell
supabase functions deploy delete-account
```

Pengingat lokal berjalan di Android setelah izin notifikasi diberikan. Push FCM
belum aktif sampai proyek Firebase Android dikonfigurasi dan token perangkat
diintegrasikan.
