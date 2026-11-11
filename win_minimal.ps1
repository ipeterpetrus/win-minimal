<#
 win_minimal.ps1 - Windows 11 "tweak minimal", tanpa UI.
 -Preset Minimal = preset Minimal Chris Titus WinUtil 26.10.28 (ConsumerFeatures, WPBT, Telemetry, Services), diambil dari
 salinan yang sudah diaudit, MINUS env POWERSHELL_TELEMETRY_OPTOUT (tak berefek di Windows PowerShell 5.1).
 -Preset Lean (DEFAULT) = Minimal + Widgets/Copilot/saran web Start/aplikasi latar/CrossDeviceResume mati,
   Edge/Chrome tanpa mode latar + autostart browser dihapus, layanan Intel esrv_svc/DSAService Disabled.
   Memory Integrity / VBS TIDAK disentuh (keputusan keamanan pemilik).
 Pengaman tambahan:
   - snapshot nilai lama (registri + jenisnya, layanan, Defender) ditulis SEBELUM perubahan pertama; gagal tulis = batal;
   - snapshot memuat SID; Undo menolak bila dijalankan user lain (HKCU milik user yang menjalankan Apply);
   - layanan TIDAK PERNAH dilonggarkan (Disabled tidak dijadikan Manual);
   - setiap perubahan dibaca ulang sebelum dicatat berhasil; restore point dicek benar-benar bertambah.
 Berkas ini ASCII murni: Windows PowerShell 5.1 membaca .ps1 tanpa BOM sebagai ANSI.
 Tidak menyentuh: Defender real-time, Windows Update, firewall, OpenSSH, Steam/game, Edge/OneDrive, BitLocker, boot.

 Pakai (PowerShell sebagai Administrator) - lihat README untuk URL ber-commit dan cara verifikasi SHA-256:
   .\win_minimal.ps1 [-Mode Apply|Audit|Undo]
   & ([scriptblock]::Create((irm <raw-url>))) -Mode Audit
#>
param([ValidateSet('Audit', 'Apply', 'Undo')][string]$Mode = 'Apply', [ValidateSet('Lean', 'Minimal')][string]$Preset = 'Lean')

function Invoke-WinMinimal([string]$Mode, [string]$Preset) {
    $ErrorActionPreference = 'Stop'
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Jalankan PowerShell sebagai Administrator.'; return
    }
    $dir = 'C:\ProgramData\winopt'; $logf = "$dir\minimal_log.txt"; $undof = "$dir\minimal_undo.json"
    function L($m) { $t = (Get-Date -Format s) + " [$Mode] " + $m; if ($Mode -ne 'Audit') { Add-Content $logf $t }; Write-Host $t }

    # --- preset Minimal WinUtil 26.10.28 ---
    $reg = @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures', 1),
        @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager', 'DisableWpbtExecution', 1),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled', 0),
        @('HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy', 'HasAccepted', 0),
        @('HKCU:\Software\Microsoft\Input\TIPC', 'Enabled', 0),
        @('HKCU:\Software\Microsoft\InputPersonalization', 'RestrictImplicitInkCollection', 1),
        @('HKCU:\Software\Microsoft\InputPersonalization', 'RestrictImplicitTextCollection', 1),
        @('HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore', 'HarvestContacts', 0),
        @('HKCU:\Software\Microsoft\Personalization\Settings', 'AcceptedPrivacyPolicy', 0),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection', 'AllowTelemetry', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_TrackProgs', 0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'PublishUserActivities', 0),
        @('HKCU:\Software\Microsoft\Siuf\Rules', 'NumberOfSIUFInPeriod', 0)
    )
    $regRemove = , @('HKCU:\Software\Microsoft\Siuf\Rules', 'PeriodInNanoSeconds')   # koma unary: tetap 1 pasangan
    if (-not ($regRemove.Count -eq 1 -and $regRemove[0].Count -eq 2)) { throw 'bentuk regRemove rusak' }
    $svc = [ordered]@{ DiagTrack = 'Disabled'; WerSvc = 'Disabled'; CscService = 'Disabled'; SharedAccess = 'Disabled'; MapsBroker = 'Manual'; StorSvc = 'Manual' }
    $rank = @{ Automatic = 3; Manual = 2; Disabled = 1 }

    # --- preset Lean (default) = Minimal + pemangkas RAM/latar belakang yang aman dan bisa di-Undo ---
    if ($Preset -eq 'Lean') {
        $reg += @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0),   # Widgets mati (kunci sering dikunci Windows; dilewati bila sudah 0)
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
            @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
            @('HKCU:\Software\Policies\Microsoft\Windows\Explorer', 'DisableSearchBoxSuggestions', 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'BingSearchEnabled', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications', 'GlobalUserDisabled', 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsResumeAllowed', 0),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 0),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 0),
            @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'BackgroundModeEnabled', 0),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0)
        )
        foreach ($e in @(Get-Service -Name 'ESRV_SVC*' -ErrorAction SilentlyContinue)) { $svc[$e.Name] = 'Disabled' }   # Intel SUR / Energy Server (telemetri)
        $svc['DSAService'] = 'Disabled'   # Intel Driver & Support Assistant (pembaru latar)
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'   # autostart browser dihapus (nilai lama ke snapshot)
        if (Test-Path $runKey) {
            foreach ($n in (Get-Item $runKey).GetValueNames()) {
                if ($n -match '^(GoogleChromeAutoLaunch_|MicrosoftEdgeAutoLaunch_)') { $regRemove += , @($runKey, $n) }
            }
        }
    }

    function Get-Reg($p, $n) {
        if (-not (Test-Path $p)) { return @{ exists = $false } }
        $k = Get-Item -Path $p
        if ($k.GetValueNames() -notcontains $n) { return @{ exists = $false } }
        return @{ exists = $true; value = $k.GetValue($n); kind = [string]$k.GetValueKind($n) }
    }

    if ($Mode -eq 'Audit') {
        foreach ($r in $reg) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target={3}" -f $r[0], $r[1], $(if ($g.exists) { $g.value } else { '<tak ada>' }), $r[2]) }
        foreach ($r in $regRemove) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target=<hapus>" -f $r[0], $r[1], $(if ($g.exists) { $g.value } else { '<tak ada>' })) }
        foreach ($k in $svc.Keys) { $s = Get-Service $k -ErrorAction SilentlyContinue; L ("layanan {0} sekarang={1} target={2}" -f $k, $(if ($s) { $s.StartType } else { '<tak ada>' }), $svc[$k]) }
        L ("Defender SubmitSamplesConsent sekarang=" + (Get-MpPreference).SubmitSamplesConsent + " target=2")
        return
    }
    New-Item -ItemType Directory -Force $dir | Out-Null

    if ($Mode -eq 'Undo') {
        if (-not (Test-Path $undof)) { L 'tidak ada minimal_undo.json - tak ada yang dikembalikan'; return }
        $u = Get-Content $undof -Raw | ConvertFrom-Json
        if ($u.sid -ne $id.User.Value) { L "DITOLAK: snapshot milik SID $($u.sid), bukan user ini ($($id.User.Value))"; return }
        $uf = 0
        foreach ($r in $u.reg) {
            try {
                $g = Get-Reg $r.path $r.name
                if (-not $r.exists) {
                    if ($g.exists) { Remove-ItemProperty -Path $r.path -Name $r.name; L "reg $($r.path)\$($r.name) dihapus (semula tak ada)" }
                } elseif ($g.exists -and "$($g.value)" -eq "$($r.value)") { L "reg $($r.path)\$($r.name) sudah $($r.value)" }
                else {
                    if (-not (Test-Path $r.path)) { New-Item -Path $r.path -Force | Out-Null }
                    New-ItemProperty -Path $r.path -Name $r.name -Value $r.value -PropertyType $r.kind -Force | Out-Null
                    L "reg $($r.path)\$($r.name) = $($r.value) ($($r.kind))"
                }
            } catch { $uf++; L "GAGAL undo reg $($r.path)\$($r.name): $($_.Exception.Message)" }
        }
        foreach ($s in $u.svc) { try { Set-Service -Name $s.name -StartupType $s.old; L "layanan $($s.name) -> $($s.old)" } catch { $uf++; L "GAGAL undo layanan $($s.name): $($_.Exception.Message)" } }
        if ($null -ne $u.submit) { try { Set-MpPreference -SubmitSamplesConsent $u.submit; L "Defender SubmitSamplesConsent = $($u.submit)" } catch { $uf++; L "GAGAL undo Defender" } }
        if ($uf -eq 0) { Move-Item $undof ("$undof.done-" + (Get-Date -Format yyyyMMddHHmmss)) -Force; L 'UNDO selesai (snapshot diarsipkan; Apply berikutnya membuat snapshot baru)' }
        else { L "UNDO selesai dengan $uf gagal; snapshot DIPERTAHANKAN supaya bisa diulang" }
        return
    }

    # --- Apply ---
    L "APPLY mulai (preset $Preset)"
    # snapshot: nilai ASLI pertama dipertahankan; entri yang belum tercatat (mis. Lean sesudah Minimal) ditambahkan
    if (Test-Path $undof) {
        $old = Get-Content $undof -Raw | ConvertFrom-Json
        if ($old.sid -ne $id.User.Value) { throw "snapshot milik SID $($old.sid), bukan user ini - APPLY dibatalkan" }
        $snap = @{ sid = $old.sid; user = $old.user; reg = @($old.reg); svc = @($old.svc); submit = $old.submit }
        L 'snapshot lama dipertahankan; entri baru ditambahkan'
    } else {
        $snap = @{ sid = $id.User.Value; user = $id.Name; reg = @(); svc = @(); submit = (Get-MpPreference).SubmitSamplesConsent }
    }
    $seen = @{}; foreach ($e in $snap.reg) { $seen[$e.path + '|' + $e.name] = 1 }
    foreach ($r in ($reg + $regRemove)) {
        if ($seen.ContainsKey($r[0] + '|' + $r[1])) { continue }
        $g = Get-Reg $r[0] $r[1]; $snap.reg += @{ path = $r[0]; name = $r[1]; exists = $g.exists; value = $g.value; kind = $g.kind }
    }
    $seenS = @{}; foreach ($e in $snap.svc) { $seenS[$e.name] = 1 }
    foreach ($k in $svc.Keys) { if ($seenS.ContainsKey($k)) { continue }; $s = Get-Service $k -ErrorAction SilentlyContinue; if ($s) { $snap.svc += @{ name = $k; old = [string]$s.StartType } } }
    $snap | ConvertTo-Json -Depth 4 | Set-Content $undof
    if (-not (Test-Path $undof)) { throw 'snapshot gagal ditulis - APPLY dibatalkan' }
    L "snapshot nilai lama ditulis SEBELUM perubahan: $undof (preset $Preset)"
    try {
        $before = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
        Enable-ComputerRestore -Drive 'C:\'
        Checkpoint-Computer -Description 'win-minimal sebelum' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
        $after = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue).Count
        if ($after -gt $before) { L 'restore point dibuat' } else { L 'restore point TIDAK bertambah (batas 1/24 jam?) - snapshot JSON tetap titik balik' }
    } catch { L "restore point GAGAL: $($_.Exception.Message) - snapshot JSON tetap titik balik" }

    $fail = 0
    foreach ($r in $reg) {
        $g0 = Get-Reg $r[0] $r[1]
        if ($g0.exists -and $g0.value -eq $r[2]) { L ("reg {0}\{1} sudah {2}" -f $r[0], $r[1], $r[2]); continue }
        try {
            if (-not (Test-Path $r[0])) { New-Item -Path $r[0] -Force | Out-Null }
            New-ItemProperty -Path $r[0] -Name $r[1] -Value $r[2] -PropertyType DWord -Force | Out-Null
            $g = Get-Reg $r[0] $r[1]
            if ($g.exists -and $g.value -eq $r[2]) { L ("reg {0}\{1} = {2}" -f $r[0], $r[1], $r[2]) } else { $fail++; L ("GAGAL verifikasi reg {0}\{1}" -f $r[0], $r[1]) }
        } catch { $fail++; L ("GAGAL reg {0}\{1}: {2}" -f $r[0], $r[1], $_.Exception.Message) }
    }
    foreach ($r in $regRemove) {
        if ((Get-Reg $r[0] $r[1]).exists) {
            try { Remove-ItemProperty -Path $r[0] -Name $r[1]; L "reg $($r[0])\$($r[1]) dihapus" } catch { $fail++; L "GAGAL hapus $($r[1]): $($_.Exception.Message)" }
        }
    }
    foreach ($k in $svc.Keys) {
        $s = Get-Service $k -ErrorAction SilentlyContinue
        if (-not $s) { L "layanan $k tidak ada, dilewati"; continue }
        $cur = [string]$s.StartType; $want = $svc[$k]
        if ($null -eq $rank[$cur]) { L "layanan $k StartType $cur tak dikenal, dilewati"; continue }
        if ($rank[$cur] -eq $rank[$want]) { L "layanan $k sudah $want"; continue }
        if ($rank[$cur] -lt $rank[$want]) { L "layanan $k sudah $cur (lebih ketat; tidak dilonggarkan ke $want)"; continue }
        try {
            if ($want -eq 'Disabled') { Stop-Service $k -Force -ErrorAction SilentlyContinue }
            Set-Service -Name $k -StartupType $want
            if ([string](Get-Service $k).StartType -eq $want) { L "layanan $k $cur -> $want" } else { $fail++; L "GAGAL verifikasi layanan $k" }
        } catch { $fail++; L "GAGAL layanan ${k}: $($_.Exception.Message)" }
    }
    try {
        Set-MpPreference -SubmitSamplesConsent 2
        L ("Defender SubmitSamplesConsent = " + (Get-MpPreference).SubmitSamplesConsent + " (2 = jangan kirim sampel; real-time tetap ON)")
    } catch { $fail++; L "GAGAL Defender: $($_.Exception.Message)" }
    L ("APPLY selesai, gagal=$fail. Tanpa restart; efek HKCU penuh sesudah logoff/logon.")
}

Invoke-WinMinimal -Mode $Mode -Preset $Preset
