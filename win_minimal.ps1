<#
 win_minimal.ps1 - Windows 11 lebih ringan tanpa UI, dengan Undo. Berkas ini ASCII murni (Windows PowerShell 5.1
 membaca .ps1 tanpa BOM sebagai ANSI).

 -Preset Minimal : nilai preset Minimal Chris Titus WinUtil 26.10.28 (ConsumerFeatures, WPBT, Telemetry, Services),
                   kecuali env POWERSHELL_TELEMETRY_OPTOUT (tak berefek di PowerShell 5.1).
 -Preset Lean    : (default) Minimal + Widgets, Copilot, saran web di Start, aplikasi latar, CrossDeviceResume mati;
                   Edge/Chrome tanpa mode latar; autostart browser di HKCU\Run dihapus; layanan Intel SUR
                   (ESRV_SVC*, SystemUsageReportSvc_*) dan DSAService Disabled; PresentMonSharedService Manual.
 Tidak disentuh: Defender real-time, Windows Update, firewall, OpenSSH, driver, Steam/game, BitLocker, boot,
                 Memory Integrity/VBS, System Restore (restore point dibuat hanya bila sudah aktif).

 Undo: snapshot (nilai + jenis registri, kunci yang dibuat, StartType + status layanan, Defender) ditulis SEBELUM
 perubahan ke C:\ProgramData\winopt (folder dipaksa milik Administrators/SYSTEM; folder milik user lain = berhenti).
 Undo hanya menyentuh entri yang ada di daftar skrip ini (snapshot tak bisa dipakai menulis registri lain).
 Exit code (bila dijalankan sebagai berkas): 0 sukses, 1 ada yang gagal, 2 ditolak (bukan admin / folder / SID).
#>
param([ValidateSet('Audit', 'Apply', 'Undo')][string]$Mode = 'Apply', [ValidateSet('Lean', 'Minimal')][string]$Preset = 'Lean')

function Invoke-WinMinimal([string]$Mode, [string]$Preset) {
    $ErrorActionPreference = 'Stop'
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Jalankan PowerShell sebagai Administrator.'; return 2
    }
    $dir = 'C:\ProgramData\winopt'; $logf = "$dir\minimal_log.txt"; $undof = "$dir\minimal_undo.json"

    # --- folder snapshot: harus milik Administrators/SYSTEM, tanpa izin tulis untuk user biasa ---
    $adminSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $sysSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    if ($Mode -ne 'Audit') {
        if (Test-Path $dir) {
            $acl = Get-Acl $dir
            $owner = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier])
            if ($owner -ne $adminSid -and $owner -ne $sysSid) { Write-Host "DITOLAK: $dir dimiliki $($acl.Owner), bukan Administrators/SYSTEM"; return 2 }
        } else { New-Item -ItemType Directory $dir | Out-Null }
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetOwner($adminSid); $acl.SetAccessRuleProtection($true, $false)
        foreach ($s in $adminSid, $sysSid) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        }
        Set-Acl $dir $acl
    }
    function L($m) { $t = (Get-Date -Format s) + " [$Mode] " + $m; if ($Mode -ne 'Audit') { Add-Content $logf $t }; Write-Host $t }

    # --- daftar perubahan ---
    function Get-Lists([string]$P) {
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
        $rem = , @('HKCU:\Software\Microsoft\Siuf\Rules', 'PeriodInNanoSeconds')   # koma unary: tetap 1 pasangan
        $svc = [ordered]@{ DiagTrack = 'Disabled'; WerSvc = 'Disabled'; CscService = 'Disabled'; SharedAccess = 'Disabled'; MapsBroker = 'Manual'; StorSvc = 'Manual' }
        if ($P -eq 'Lean') {
            $reg += @(
                @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0),
                @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
                @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
                @('HKCU:\Software\Policies\Microsoft\Windows\Explorer', 'DisableSearchBoxSuggestions', 1),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'BingSearchEnabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications', 'GlobalUserDisabled', 1),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsResumeAllowed', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsOneDriveResumeAllowed', 0),
                @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 0),
                @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 0),
                @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'BackgroundModeEnabled', 0),
                @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0)
            )
            foreach ($e in @(Get-Service -Name 'ESRV_SVC*', 'SystemUsageReportSvc_*' -ErrorAction SilentlyContinue)) { $svc[$e.Name] = 'Disabled' }
            $svc['DSAService'] = 'Disabled'
            $svc['PresentMonSharedService'] = 'Manual'
            $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
            if (Test-Path $runKey) {
                foreach ($n in (Get-Item $runKey).GetValueNames()) { if ($n -match '^(GoogleChromeAutoLaunch_|MicrosoftEdgeAutoLaunch_)') { $rem += , @($runKey, $n) } }
            }
        }
        return @{ reg = $reg; rem = $rem; svc = $svc }
    }
    $lists = Get-Lists $Preset
    $reg = $lists.reg; $regRemove = $lists.rem; $svc = $lists.svc
    $rank = @{ Automatic = 3; Manual = 2; Disabled = 1 }

    function Get-Reg($p, $n) {
        if (-not (Test-Path $p)) { return @{ exists = $false } }
        $k = Get-Item -Path $p
        if ($k.GetValueNames() -notcontains $n) { return @{ exists = $false } }
        return @{ exists = $true; value = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); kind = [string]$k.GetValueKind($n) }
    }
    function Get-Submit { try { (Get-MpPreference).SubmitSamplesConsent } catch { $null } }

    if ($Mode -eq 'Audit') {
        foreach ($r in $reg) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target={3}" -f $r[0], $r[1], $(if ($g.exists) { "$($g.value) ($($g.kind))" } else { '<tak ada>' }), $r[2]) }
        foreach ($r in $regRemove) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target=<hapus>" -f $r[0], $r[1], $(if ($g.exists) { "$($g.value) ($($g.kind))" } else { '<tak ada>' })) }
        foreach ($k in $svc.Keys) { $s = Get-Service $k -ErrorAction SilentlyContinue; L ("layanan {0} sekarang={1} target={2}" -f $k, $(if ($s) { "$($s.StartType)/$($s.Status)" } else { '<tak ada>' }), $svc[$k]) }
        L ("Defender SubmitSamplesConsent sekarang=" + (Get-Submit) + " target=2")
        return 0
    }

    if ($Mode -eq 'Undo') {
        if (-not (Test-Path $undof)) { L 'tidak ada minimal_undo.json - tak ada yang dikembalikan'; return 0 }
        $u = Get-Content $undof -Raw | ConvertFrom-Json
        if ($u.sid -ne $id.User.Value) { L "DITOLAK: snapshot milik SID $($u.sid), bukan user ini ($($id.User.Value))"; return 2 }
        # hanya entri yang dikenal skrip ini (kedua preset) yang boleh disentuh Undo
        $known = Get-Lists 'Lean'; $okReg = @{}; $okSvc = @{}
        foreach ($r in ($known.reg + $known.rem)) { $okReg[$r[0] + '|' + $r[1]] = 1 }
        foreach ($k in $known.svc.Keys) { $okSvc[$k] = 1 }
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $uf = 0
        foreach ($r in $u.reg) {
            $isRun = ($r.path -eq $runKey -and $r.name -match '^(GoogleChromeAutoLaunch_|MicrosoftEdgeAutoLaunch_)')
            if (-not ($okReg.ContainsKey($r.path + '|' + $r.name) -or $isRun)) { $uf++; L "DITOLAK entri tak dikenal di snapshot: $($r.path)\$($r.name)"; continue }
            try {
                $g = Get-Reg $r.path $r.name
                if (-not $r.exists) {
                    if ($g.exists) { Remove-ItemProperty -Path $r.path -Name $r.name; L "reg $($r.path)\$($r.name) dihapus (semula tak ada)" }
                } elseif ($g.exists -and $g.kind -eq $r.kind -and "$($g.value)" -eq "$($r.value)") { L "reg $($r.path)\$($r.name) sudah $($r.value) ($($r.kind))" }
                else {
                    if (-not (Test-Path $r.path)) { New-Item -Path $r.path -Force | Out-Null }
                    New-ItemProperty -Path $r.path -Name $r.name -Value $r.value -PropertyType $r.kind -Force | Out-Null
                    L "reg $($r.path)\$($r.name) = $($r.value) ($($r.kind))"
                }
            } catch { $uf++; L "GAGAL undo reg $($r.path)\$($r.name): $($_.Exception.Message)" }
        }
        foreach ($p in @($u.newkeys)) {   # kunci yang DIBUAT Apply: hapus bila kosong
            if (-not $p) { continue }
            try { if ((Test-Path $p) -and -not (Get-Item $p).GetValueNames() -and -not (Get-ChildItem $p)) { Remove-Item $p; L "kunci $p dihapus (dibuat oleh Apply)" } }
            catch { $uf++; L "GAGAL hapus kunci ${p}: $($_.Exception.Message)" }
        }
        foreach ($s in $u.svc) {
            if (-not $okSvc.ContainsKey($s.name) -and $s.name -notmatch '^(ESRV_SVC|SystemUsageReportSvc_)') { $uf++; L "DITOLAK layanan tak dikenal: $($s.name)"; continue }
            try {
                Set-Service -Name $s.name -StartupType $s.old
                if ($s.status -eq 'Running' -and (Get-Service $s.name).Status -ne 'Running') { Start-Service $s.name }
                L "layanan $($s.name) -> $($s.old)/$($s.status)"
            } catch { $uf++; L "GAGAL undo layanan $($s.name): $($_.Exception.Message)" }
        }
        if ($null -ne $u.submit) {
            try { Set-MpPreference -SubmitSamplesConsent $u.submit; if ((Get-Submit) -eq $u.submit) { L "Defender SubmitSamplesConsent = $($u.submit)" } else { $uf++; L 'GAGAL verifikasi Defender' } }
            catch { $uf++; L "GAGAL undo Defender: $($_.Exception.Message)" }
        }
        if ($uf -eq 0) { Move-Item $undof ("$undof.done-" + (Get-Date -Format yyyyMMddHHmmss)) -Force; L 'UNDO selesai (snapshot diarsipkan)'; return 0 }
        L "UNDO selesai dengan $uf gagal; snapshot DIPERTAHANKAN supaya bisa diulang"; return 1
    }

    # --- Apply ---
    L "APPLY mulai (preset $Preset)"
    if (Test-Path $undof) {
        $old = Get-Content $undof -Raw | ConvertFrom-Json
        if ($old.sid -ne $id.User.Value) { L "DITOLAK: snapshot milik SID $($old.sid), bukan user ini"; return 2 }
        $snap = @{ sid = $old.sid; user = $old.user; reg = @($old.reg); svc = @($old.svc); newkeys = @($old.newkeys | Where-Object { $_ }); submit = $old.submit }
        L 'snapshot lama dipertahankan (nilai ASLI pertama); entri baru ditambahkan'
    } else {
        $snap = @{ sid = $id.User.Value; user = $id.Name; reg = @(); svc = @(); newkeys = @(); submit = (Get-Submit) }
    }
    $seen = @{}; foreach ($e in $snap.reg) { $seen[$e.path + '|' + $e.name] = 1 }
    foreach ($r in ($reg + $regRemove)) {
        if ($seen.ContainsKey($r[0] + '|' + $r[1])) { continue }
        $g = Get-Reg $r[0] $r[1]; $snap.reg += @{ path = $r[0]; name = $r[1]; exists = $g.exists; value = $g.value; kind = $g.kind }
        if (-not (Test-Path $r[0]) -and $snap.newkeys -notcontains $r[0]) { $snap.newkeys += $r[0] }
    }
    $seenS = @{}; foreach ($e in $snap.svc) { $seenS[$e.name] = 1 }
    foreach ($k in $svc.Keys) { if ($seenS.ContainsKey($k)) { continue }; $s = Get-Service $k -ErrorAction SilentlyContinue; if ($s) { $snap.svc += @{ name = $k; old = [string]$s.StartType; status = [string]$s.Status } } }
    $tmp = "$undof.tmp"
    $snap | ConvertTo-Json -Depth 4 | Set-Content $tmp -Encoding UTF8
    $null = Get-Content $tmp -Raw | ConvertFrom-Json   # gagal parse = berhenti sebelum perubahan apa pun
    Move-Item $tmp $undof -Force
    L "snapshot ditulis SEBELUM perubahan: $undof"

    try {
        $before = @(Get-ComputerRestorePoint -ErrorAction Stop).Count
        Checkpoint-Computer -Description 'win-minimal sebelum' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
        if (@(Get-ComputerRestorePoint).Count -gt $before) { L 'restore point dibuat' } else { L 'restore point tidak dibuat (batas 1/24 jam) - snapshot tetap titik balik' }
    } catch { L 'System Restore tidak aktif / tidak tersedia - dilewati (tidak dinyalakan diam-diam); snapshot tetap titik balik' }

    $fail = 0
    foreach ($r in $reg) {
        $g0 = Get-Reg $r[0] $r[1]
        if ($g0.exists -and $g0.kind -eq 'DWord' -and $g0.value -eq $r[2]) { L ("reg {0}\{1} sudah {2}" -f $r[0], $r[1], $r[2]); continue }
        try {
            if (-not (Test-Path $r[0])) { New-Item -Path $r[0] -Force | Out-Null }
            New-ItemProperty -Path $r[0] -Name $r[1] -Value $r[2] -PropertyType DWord -Force | Out-Null
            $g = Get-Reg $r[0] $r[1]
            if ($g.exists -and $g.kind -eq 'DWord' -and $g.value -eq $r[2]) { L ("reg {0}\{1} = {2}" -f $r[0], $r[1], $r[2]) } else { $fail++; L ("GAGAL verifikasi reg {0}\{1}" -f $r[0], $r[1]) }
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
            if ($want -eq 'Disabled') { Stop-Service $k -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
            Set-Service -Name $k -StartupType $want
            if ([string](Get-Service $k).StartType -eq $want) { L "layanan $k $cur -> $want" } else { $fail++; L "GAGAL verifikasi layanan $k" }
        } catch { $fail++; L "GAGAL layanan ${k}: $($_.Exception.Message)" }
    }
    try {
        Set-MpPreference -SubmitSamplesConsent 2
        if ((Get-Submit) -eq 2) { L 'Defender SubmitSamplesConsent = 2 (jangan kirim sampel; real-time tetap ON)' } else { $fail++; L 'GAGAL verifikasi Defender (Tamper Protection?)' }
    } catch { $fail++; L "GAGAL Defender: $($_.Exception.Message)" }
    L ("APPLY selesai, gagal=$fail. Tanpa restart; sebagian efek (Start, Widgets, aplikasi latar) terasa sesudah sign out / restart.")
    if ($fail -gt 0) { return 1 } else { return 0 }
}

$rc = Invoke-WinMinimal -Mode $Mode -Preset $Preset
if ($PSCommandPath) { exit $rc }   # sebagai berkas: kembalikan exit code; lewat irm|iex: jangan tutup jendela pengguna
