# win-minimal

Tweak Windows 11 ke paling ringan, **tanpa UI**, dan **semua bisa dikembalikan** (Undo).
Diuji di Windows 11 (PowerShell 5.1) pada PC ASUS Z690 + RTX 3070 Ti: Apply → Undo → hasil identik dengan keadaan awal.

## Cara menjalankan (langkah demi langkah)

1. Klik kanan tombol **Start** → pilih **Terminal (Admin)** atau **Windows PowerShell (Admin)** → **Yes**.
2. Tempel **satu baris** ini lalu Enter (preset **Lean**, default):

```powershell
irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/af4e1b5e3e3d9dae14b1d25dd9789ecf510cd1e7/win_minimal.ps1 | iex
```

3. Tunggu sampai muncul `APPLY selesai, gagal=0`. Tidak perlu restart, tetapi sebagian efek (Start, Widgets, aplikasi latar) baru terasa sesudah **sign out / restart**.

## Pilihan lain

Unduh dulu lalu cek SHA-256 (paling aman):

```powershell
irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/af4e1b5e3e3d9dae14b1d25dd9789ecf510cd1e7/win_minimal.ps1 -OutFile $env:TEMP\win_minimal.ps1
(Get-FileHash $env:TEMP\win_minimal.ps1 -Algorithm SHA256).Hash
# harus: DEE08AFE788257FBB2B5820AD134E056BE7694AF368F6B978E9985998CF3B1F2
```

Lalu jalankan salah satu:

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1 -Mode Audit                    # lihat saja, tidak mengubah apa pun
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1                                # Apply preset Lean (default)
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1 -Preset Minimal                # hanya preset Minimal WinUtil
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1 -Mode Undo                     # kembalikan semua ke nilai semula
```

## Isi preset

**Minimal** (sama dengan preset Minimal Chris Titus WinUtil 26.10.28): matikan iklan/saran aplikasi (ConsumerFeatures),
WPBT, telemetri (registri privasi + layanan DiagTrack/WerSvc), layanan CscService/SharedAccess Disabled, MapsBroker/StorSvc Manual,
Defender tidak mengirim sampel (proteksi real-time tetap ON).

**Lean** (default) = Minimal + Widgets, Copilot, saran web/Bing di Start, aplikasi latar belakang, CrossDeviceResume dimatikan;
Edge/Chrome tanpa mode latar (StartupBoost/BackgroundMode); autostart browser di HKCU\Run dihapus;
layanan Intel SUR (`ESRV_SVC*`) dan Intel Driver & Support Assistant (`DSAService`) Disabled.

## Pengaman

- nilai lama (registri + jenisnya, layanan, Defender) disimpan ke `C:\ProgramData\winopt\minimal_undo.json` **sebelum** perubahan;
- Undo hanya untuk user yang sama (dicek SID); gagal sebagian = snapshot dipertahankan supaya bisa diulang;
- layanan tidak pernah dilonggarkan (yang sudah Disabled tidak dijadikan Manual); nilai yang sudah sesuai tidak ditulis ulang;
- setiap perubahan dibaca ulang sebelum dicatat berhasil; restore point dicek benar-benar dibuat;
- **tidak menyentuh**: Defender real-time, Windows Update, firewall, OpenSSH, Steam/game, driver, Edge/OneDrive (tidak dihapus), BitLocker,
  boot, Memory Integrity/VBS.

Log: `C:\ProgramData\winopt\minimal_log.txt`.

## Soal "RAM terpakai"

Windows memakai RAM kosong sebagai cache (*Standby*); itu **bukan** pemborosan dan otomatis dilepas saat aplikasi butuh.
Yang dihitung adalah *In use*. Pemakan terbesar biasanya aplikasi yang sedang terbuka (mis. Steam ±1,3 GB), Defender, dan driver GPU.
Script ini memangkas latar belakang Windows; aplikasi yang Anda buka sendiri tetap memakai RAM-nya.

Commit ini: `af4e1b5e3e3d9dae14b1d25dd9789ecf510cd1e7` · SHA-256 `DEE08AFE788257FBB2B5820AD134E056BE7694AF368F6B978E9985998CF3B1F2`
