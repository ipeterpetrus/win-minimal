# win-minimal

Membuat Windows 11 lebih ringan **tanpa UI**, dengan **Undo**. Satu skrip PowerShell, ASCII murni, diuji di
Windows 11 + PowerShell 5.1 (PC ASUS Z690, RTX 3070 Ti): Apply lalu Undo menghasilkan keadaan yang sama dengan semula,
dan OpenSSH, Wake-on-LAN, Windows Update, Defender real-time, serta Steam tetap berjalan.

## Cara pakai (paling aman, disarankan)

1. Klik kanan **Start** → **Terminal (Admin)** atau **Windows PowerShell (Admin)** → **Yes**.
2. Tempel blok ini lalu Enter. Ia mengunduh versi yang dikunci, **mencocokkan sidik SHA-256 secara otomatis**
   (berhenti bila beda), lalu menjalankan preset **Lean**:

```powershell
$u='https://raw.githubusercontent.com/ipeterpetrus/win-minimal/31fe589519cc5cf136c9b92162ad5037ec8ed2c6/win_minimal.ps1'; $h='878B07FB633DCF8FE3BB32692763ECDD662F374EBB2B5EA7B02EE92C16D80408'; $f="$env:TEMP\win_minimal.ps1"; irm $u -OutFile $f; if ((Get-FileHash $f -Algorithm SHA256).Hash -ne $h) { throw 'SHA-256 beda, dibatalkan' }; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

3. Tunggu baris `APPLY selesai, gagal=0`, lalu **sign out atau restart** supaya efek Start/Widgets/aplikasi latar terasa.

## Mengembalikan (Undo)

Di PowerShell (Admin), dengan **akun Windows yang sama** seperti saat Apply:

```powershell
$u='https://raw.githubusercontent.com/ipeterpetrus/win-minimal/31fe589519cc5cf136c9b92162ad5037ec8ed2c6/win_minimal.ps1'; $h='878B07FB633DCF8FE3BB32692763ECDD662F374EBB2B5EA7B02EE92C16D80408'; $f="$env:TEMP\win_minimal.ps1"; irm $u -OutFile $f; if ((Get-FileHash $f -Algorithm SHA256).Hash -ne $h) { throw 'SHA-256 beda, dibatalkan' }; powershell -NoProfile -ExecutionPolicy Bypass -File $f -Mode Undo
```

## Pilihan lain

Ganti akhir baris di atas dengan salah satu:

| Akhiran | Fungsi |
|---|---|
| `-Mode Audit` | Hanya melihat nilai sekarang vs target, tidak mengubah apa pun |
| `-Preset Minimal` | Hanya preset Minimal WinUtil (lebih sedikit perubahan) |
| `-Mode Undo` | Kembalikan semua ke nilai sebelum Apply pertama |

Singkat tanpa cek SHA-256 (kurang aman): `irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/31fe589519cc5cf136c9b92162ad5037ec8ed2c6/win_minimal.ps1 | iex`

Exit code saat dijalankan sebagai berkas: `0` sukses, `1` ada yang gagal, `2` ditolak (bukan Admin / folder snapshot bukan milik Administrators / akun beda).
Log: `C:\ProgramData\winopt\minimal_log.txt`.

## Apa yang diubah

**Preset Minimal** (nilai dari preset Minimal Chris Titus WinUtil 26.10.28, kecuali env `POWERSHELL_TELEMETRY_OPTOUT` yang tak berefek di PowerShell 5.1):
iklan/saran aplikasi (ConsumerFeatures) mati, WPBT mati, pengaturan privasi/telemetri (13 nilai registri),
layanan DiagTrack, WerSvc, CscService, SharedAccess = Disabled; MapsBroker, StorSvc = Manual; Defender tidak mengirim sampel.

**Preset Lean** (default) = Minimal + Widgets, Copilot, saran web/Bing di Start, aplikasi latar belakang, CrossDeviceResume dimatikan;
Edge/Chrome tanpa mode latar; autostart Chrome/Edge di `HKCU\Run` dihapus; layanan Intel SUR (`ESRV_SVC*`, `SystemUsageReportSvc_*`)
dan Intel Driver & Support Assistant (`DSAService`) Disabled; `PresentMonSharedService` Manual.

### Dampak yang perlu diketahui

| Perubahan | Akibat |
|---|---|
| SharedAccess Disabled | **Mobile hotspot / Internet Connection Sharing** Windows tidak bisa dipakai |
| CscService Disabled | **Offline Files** (berkas jaringan offline) tidak jalan |
| WerSvc Disabled | Laporan crash Windows tidak dikirim/disimpan |
| Aplikasi latar mati | Aplikasi Store (Mail, Phone Link, dll.) tidak memberi notifikasi saat ditutup |
| DSAService Disabled | Intel Driver & Support Assistant tidak memeriksa update driver otomatis |
| SubmitSamplesConsent = 2 | Defender tidak mengirim sampel file ke Microsoft (proteksi real-time tetap ON) |
| Widgets/Copilot/web di Start mati | Fitur itu hilang dari taskbar/Start |

## Yang TIDAK disentuh

Defender real-time, Windows Update, firewall, OpenSSH, driver, Steam/game, BitLocker, urutan boot, Memory Integrity/VBS,
System Restore (restore point hanya dibuat bila System Restore sudah aktif; tidak dinyalakan diam-diam).

## Keamanan

- Snapshot nilai lama ditulis **sebelum** perubahan ke `C:\ProgramData\winopt`; folder dipaksa hanya bisa diakses SYSTEM + Administrators,
  dan skrip berhenti bila folder itu dimiliki user lain.
- Undo hanya menyentuh entri yang ada di daftar skrip ini, dan hanya untuk akun yang sama (dicek SID).
- URL di atas dikunci ke satu commit; isinya tidak bisa berubah diam-diam.

## Soal "RAM terpakai"

Windows memakai RAM kosong sebagai cache (*Standby*). Itu bukan pemborosan dan dilepas otomatis saat dibutuhkan; yang penting adalah *In use*.
Contoh di PC uji (64 GB): *In use* 6,5 GB saat Steam terbuka dan sebelum skrip; 4,4 GB sesudah skrip + restart dengan Steam tertutup
(perbandingan ini tidak terkontrol: sebagian selisih adalah Steam).

## Versi

| Versi | Commit skrip | SHA-256 |
|---|---|---|
| v3 | `31fe589519cc5cf136c9b92162ad5037ec8ed2c6` | `878B07FB633DCF8FE3BB32692763ECDD662F374EBB2B5EA7B02EE92C16D80408` |

Lisensi MIT; nilai preset Minimal berasal dari [WinUtil](https://github.com/ChrisTitusTech/winutil) (MIT, CT Tech Group LLC).
