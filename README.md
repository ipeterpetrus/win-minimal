# win-minimal

Tweak minimal Windows 11, tanpa UI. Isinya hanya preset **Minimal** dari Chris Titus WinUtil 26.10.28
(ConsumerFeatures, WPBT, Telemetry, Services), ditambah pengaman:

- nilai lama disimpan ke `C:\ProgramData\winopt\minimal_undo.json` **sebelum** perubahan, jadi bisa di-Undo;
- layanan tidak pernah dilonggarkan (yang sudah Disabled tidak dijadikan Manual);
- setiap perubahan dibaca ulang sebelum dicatat berhasil; restore point dicek benar-benar dibuat;
- tidak menyentuh Defender real-time, Windows Update, firewall, OpenSSH, Steam/game, Edge/OneDrive, BitLocker, boot.

Log: `C:\ProgramData\winopt\minimal_log.txt`.

## Jalankan (PowerShell **sebagai Administrator**)

URL di bawah dipatok ke commit `c741e3c8efeb101be584ecae7f93374f4182cca5`, jadi isinya tidak bisa berubah diam-diam.

Cara paling aman: unduh, cek SHA-256, lalu jalankan berkas lokal.

```powershell
irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/c741e3c8efeb101be584ecae7f93374f4182cca5/win_minimal.ps1 -OutFile $env:TEMP\win_minimal.ps1
(Get-FileHash $env:TEMP\win_minimal.ps1 -Algorithm SHA256).Hash   # harus D601E3823514692BE9B2AF1C8C170F2A41EB84EA158172D5D8C6850A9BAAE555
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1 -Mode Audit   # lihat dulu, tanpa mengubah
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1                # Apply
```

Satu baris (langsung Apply):

```powershell
irm https://raw.githubusercontent.com/ipeterpetrus/win-minimal/c741e3c8efeb101be584ecae7f93374f4182cca5/win_minimal.ps1 | iex
```

Kembalikan ke nilai semula (user yang sama dengan saat Apply):

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\win_minimal.ps1 -Mode Undo
```

Versi terbaru selalu dicatat di README ini dengan commit + SHA-256 baru.
