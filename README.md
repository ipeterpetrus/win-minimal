# win-minimal

[![test](https://github.com/ipeterpetrus/win-minimal/actions/workflows/test.yml/badge.svg)](https://github.com/ipeterpetrus/win-minimal/actions/workflows/test.yml)

Membuat Windows 11 lebih ringan **tanpa UI**, dengan **Undo**. Satu skrip PowerShell, ASCII murni, diuji di
Windows 11 + PowerShell 5.1 (PC ASUS Z690, RTX 3070 Ti): Apply lalu Undo menghasilkan keadaan yang sama dengan semula,
dan OpenSSH, Wake-on-LAN, Windows Update, Defender real-time, serta Steam tetap berjalan.

## Cara pakai (paling aman, disarankan)

1. Klik kanan **Start** → **Terminal (Admin)** atau **Windows PowerShell (Admin)** → **Yes**.
2. Tempel blok ini lalu Enter. Ia mengunduh versi yang dikunci, **mencocokkan sidik SHA-256 secara otomatis**
   (berhenti bila beda), lalu menjalankan preset **Lean**:

```powershell
$u='https://raw.githubusercontent.com/ipeterpetrus/win-minimal/537e465f67593c462949c694fce25547e33cdb76/win_minimal.ps1'; $h='C33567CF224F04991428E6C189E7F874009107B71041DF5C5A7341E7AA09AC06'; $f="$env:TEMP\win_minimal.ps1"; irm $u -OutFile $f; if ((Get-FileHash $f -Algorithm SHA256).Hash -ne $h) { throw 'SHA-256 beda, dibatalkan' }; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

3. Tunggu baris `APPLY selesai, gagal=0`, lalu **sign out atau restart** supaya efek Start/Widgets/aplikasi latar terasa.

## Mengembalikan (Undo)

Di PowerShell (Admin), dengan **akun Windows yang sama** seperti saat Apply:

```powershell
$u='https://raw.githubusercontent.com/ipeterpetrus/win-minimal/537e465f67593c462949c694fce25547e33cdb76/win_minimal.ps1'; $h='C33567CF224F04991428E6C189E7F874009107B71041DF5C5A7341E7AA09AC06'; $f="$env:TEMP\win_minimal.ps1"; irm $u -OutFile $f; if ((Get-FileHash $f -Algorithm SHA256).Hash -ne $h) { throw 'SHA-256 beda, dibatalkan' }; powershell -NoProfile -ExecutionPolicy Bypass -File $f -Mode Undo
```

## Pilihan lain

Ganti akhir baris di atas dengan salah satu:

| Akhiran | Fungsi |
|---|---|
| `-Mode Audit` | Hanya melihat nilai sekarang vs target, tidak mengubah apa pun |
| `-Preset Minimal` | Hanya preset Minimal WinUtil (lebih sedikit perubahan) |
| `-RemoveApps` | Juga hapus aplikasi bawaan (daftar default [Win11Debloat](https://github.com/Raphire/Win11Debloat): Bing News/Weather, Solitaire, Clipchamp, Teams, Feedback Hub, Quick Assist, dll.) untuk semua user. **Tanpa Undo otomatis**; pasang ulang lewat Microsoft Store. Coba dulu dengan `-Mode Audit -RemoveApps` |
| `-Mode Undo` | Kembalikan semua ke nilai sebelum Apply pertama |

Singkat tanpa cek SHA-256 (kurang aman): `irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/537e465f67593c462949c694fce25547e33cdb76/win_minimal.ps1 | iex`

Exit code saat dijalankan sebagai berkas: `0` sukses, `1` ada yang gagal, `2` ditolak (bukan Admin / folder snapshot bukan milik Administrators / akun beda).
Log: `C:\ProgramData\winopt\minimal_log.txt`.

## Apa yang diubah

**Preset Minimal** (nilai dari preset Minimal Chris Titus WinUtil 26.10.28, kecuali env `POWERSHELL_TELEMETRY_OPTOUT` yang tak berefek di PowerShell 5.1):
iklan/saran aplikasi (ConsumerFeatures) mati, WPBT mati, pengaturan privasi/telemetri (13 nilai registri),
layanan DiagTrack, WerSvc, CscService, SharedAccess = Disabled; MapsBroker, StorSvc = Manual; Defender tidak mengirim sampel.

**Preset Lean** (default) = Minimal + Widgets, Copilot, saran web/Bing di Start, aplikasi latar belakang, CrossDeviceResume dimatikan;
Edge/Chrome tanpa mode latar; autostart Chrome/Edge dimatikan di `StartupApproved` (sama seperti Task Manager, tetap mati walau browser menulis ulang `HKCU\Run`); layanan Intel SUR (`ESRV_SVC*`, `USER_ESRV_SVC*`, `SystemUsageReportSvc_*`) + tugas terjadwal `\USER_ESRV_SVC_*` (yang menyalakan esrv di sesi user)
dan Intel Driver & Support Assistant (`DSAService`) Disabled; `PresentMonSharedService` Manual.
Sejak v5 juga: efek visual **Custom** (hanya *thumbnail* dan *font halus*; transparansi, animasi, bayangan, Aero Peek mati; menu tanpa jeda),
tips/saran/welcome experience dan notifikasi "aplikasi startup" mati, **Fast Startup mati**, dan **Game Mode ON** (bawaan Windows).

### Dampak yang perlu diketahui

| Perubahan | Akibat |
|---|---|
| Tugas/layanan Intel SUR mati | Intel System Usage Report tidak mengumpulkan data pemakaian |
| SharedAccess Disabled | **Mobile hotspot / Internet Connection Sharing** Windows tidak bisa dipakai; dilaporkan juga mengganggu jaringan NAT WSL2/Windows Sandbox (belum diuji di sini). Pakai WSL2? Setel layanan ini kembali ke Manual |
| CscService Disabled | **Offline Files** (berkas jaringan offline) tidak jalan |
| WerSvc Disabled | Laporan crash Windows tidak dikirim/disimpan |
| Aplikasi latar mati | Aplikasi Store (Mail, Phone Link, dll.) tidak memberi notifikasi saat ditutup |
| DSAService Disabled | Intel Driver & Support Assistant tidak memeriksa update driver otomatis |
| SubmitSamplesConsent = 2 | Defender tidak mengirim sampel file ke Microsoft (proteksi real-time tetap ON) |
| Widgets/Copilot/web di Start mati | Fitur itu hilang dari taskbar/Start |
| Fast Startup mati | Boot dingin sedikit lebih lama; sebagai gantinya shutdown benar-benar S5 (Wake-on-LAN konsisten, partisi NTFS tidak terkunci untuk Linux di dual-boot, update driver bersih) |
| Efek visual Custom | Tampilan lebih "datar" (tanpa animasi/transparansi); efek ke FPS game praktis nol, ke rasa responsif terasa |

## Yang TIDAK disentuh

Defender real-time, Windows Update, firewall, OpenSSH, driver, Steam/game, BitLocker, urutan boot, Memory Integrity/VBS,
System Restore (restore point hanya dibuat bila System Restore sudah aktif; tidak dinyalakan diam-diam).

## Tweak populer yang SENGAJA tidak dipakai

| Tweak | Kenapa tidak |
|---|---|
| msconfig → Boot → Advanced → *Number of processors* | Opsi debug yang hanya bisa **membatasi** jumlah core; Windows sudah memakai semua core tanpa opsi ini. Bila tercentang: hilangkan centangnya |
| msconfig → *No GUI boot* | Hanya menyembunyikan logo boot; tak mempercepat apa pun dan menyembunyikan pesan saat ada masalah |
| msconfig → *Selective startup* | Mode diagnosa. Matikan aplikasi startup lewat Task Manager → Startup apps |
| Game Mode OFF | Bawaan Windows ON; manfaatnya kecil tetapi tanpa kerugian umum. Ubah hanya bila uji di game tertentu membuktikan lebih baik |
| Power plan High/Ultimate Performance | Di CPU hibrida (Intel 12th gen ke atas) Balanced tetap boost penuh saat main game, dan lebih hemat saat idle. Selisih FPS biasanya dalam batas galat |
| Mematikan layanan Windows massal / "Number of processors" / "clear RAM" | Risiko rusak (update, Store, audio, jaringan) jauh lebih besar dari RAM yang dihemat |

## Keamanan

- Snapshot nilai lama ditulis **sebelum** perubahan ke `C:\ProgramData\winopt`; folder dipaksa hanya bisa diakses SYSTEM + Administrators,
  dan skrip berhenti bila folder itu dimiliki user lain.
- Skrip menolak jalan (exit 2) bila folder snapshot berupa junction/symlink, atau berkas di dalamnya bukan milik Administrators/SYSTEM/akun ini (diuji di CI dengan junction tanaman).
- Undo hanya menyentuh entri yang ada di daftar skrip ini, dan hanya untuk akun yang sama (dicek SID). Undo **tidak** menulis `HKCU\Run` (isinya perintah); autostart browser dinyalakan lagi lewat Task Manager bila perlu.
- Undo memulihkan entri di daftar skrip (registri, StartType+status layanan, tugas, Defender). Yang di luar daftar, misalnya aplikasi yang dihapus `-RemoveApps`, tidak termasuk.
- URL di atas dikunci ke satu commit; isinya tidak bisa berubah diam-diam.

## Soal "RAM terpakai"

Windows memakai RAM kosong sebagai cache (*Standby*). Itu bukan pemborosan dan dilepas otomatis saat dibutuhkan; yang penting adalah *In use*.
Contoh di PC uji (64 GB): *In use* 6,5 GB saat Steam terbuka dan sebelum skrip; 4,4 GB sesudah skrip + restart dengan Steam tertutup
(perbandingan ini tidak terkontrol: sebagian selisih adalah Steam).

## Versi

| Versi | Commit skrip | SHA-256 |
|---|---|---|
| v5.1 | `537e465f67593c462949c694fce25547e33cdb76` | `C33567CF224F04991428E6C189E7F874009107B71041DF5C5A7341E7AA09AC06` |
| v5 | `11bc602c8d016c8c31560eab83821445c90abe5b` | `9410E31B7776F7124DCB61F9DF0BBC928F05BCCEEF81AC5D87CE7E0691D7AAA5` |
| v4 | `2e38204844a32e14c17c1db4492f5e06524193f8` | `9F1F1CFE97C7E841A3CBC435C7320ED82E34E9605BE4FDC160FC2CAC90D9EBC3` |
| v3 | `31fe589519cc5cf136c9b92162ad5037ec8ed2c6` | `878B07FB633DCF8FE3BB32692763ECDD662F374EBB2B5EA7B02EE92C16D80408` |

Tiap push diuji otomatis di GitHub Actions (Windows PowerShell 5.1, Windows Server): cek ASCII, parse, PSScriptAnalyzer, lalu Apply → Undo kedua preset harus kembali ke keadaan asli.

Lisensi MIT; nilai preset Minimal berasal dari [WinUtil](https://github.com/ChrisTitusTech/winutil) (MIT, CT Tech Group LLC).
