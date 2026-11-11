<#
 win_minimal.ps1 - Windows 11 lebih ringan tanpa UI, dengan Undo. Berkas ini ASCII murni (Windows PowerShell 5.1
 membaca .ps1 tanpa BOM sebagai ANSI).

 -Preset Minimal : nilai preset Minimal Chris Titus WinUtil 26.10.28 (ConsumerFeatures, WPBT, Telemetry, Services),
                   kecuali env POWERSHELL_TELEMETRY_OPTOUT (tak berefek di PowerShell 5.1).
 -Preset Lean    : (default) Minimal + Widgets, Copilot, saran web di Start, aplikasi latar, CrossDeviceResume mati;
                   Edge/Chrome tanpa mode latar; autostart browser Disabled di StartupApproved (seperti Task
                   Manager; tetap mati walau browser menulis ulang HKCU\Run); layanan Intel SUR (ESRV_SVC*,
                   USER_ESRV_SVC*, SystemUsageReportSvc_* + tugas \USER_ESRV_SVC_*) dan DSAService Disabled;
                   PresentMonSharedService Manual. v5: efek visual 'Custom' (hanya thumbnail + font halus),
                   transparansi/animasi mati, MenuShowDelay 0, tips/saran/notifikasi aplikasi startup mati,
                   Fast Startup mati (dual-boot + WoL dari S5), Game Mode ON (bawaan Windows; jangan dimatikan).
 -RemoveApps     : (opsional, tanpa Undo otomatis) hapus aplikasi bawaan dari daftar default Win11Debloat
                   (Raphire, MIT) untuk semua user + provisioned. Pasang ulang lewat Microsoft Store.
 Tidak disentuh: Defender real-time, Windows Update, firewall, OpenSSH, driver, Steam/game, BitLocker, boot,
                 Memory Integrity/VBS, power plan, System Restore (restore point dibuat hanya bila sudah aktif).
 Mitos yang SENGAJA tidak dipakai: msconfig 'Number of processors' (hanya membatasi, untuk debug), 'No GUI boot',
                 Selective startup, Game Mode off, mematikan layanan Windows massal.

 Undo: snapshot (nilai + jenis registri, kunci yang dibuat, StartType + status layanan, Defender) ditulis SEBELUM
 perubahan ke C:\ProgramData\winopt (folder dipaksa milik Administrators/SYSTEM; folder milik user lain = berhenti).
 Undo hanya menyentuh entri yang ada di daftar skrip ini (snapshot tak bisa dipakai menulis registri lain).
 Exit code (bila dijalankan sebagai berkas): 0 sukses, 1 ada yang gagal, 2 ditolak (bukan admin / folder / SID).
#>
param([ValidateSet('Audit', 'Apply', 'Undo')][string]$Mode = 'Apply', [ValidateSet('Lean', 'Minimal')][string]$Preset = 'Lean', [switch]$RemoveApps)

function Invoke-WinMinimal([string]$Mode, [string]$Preset, [bool]$RemoveApps) {
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
        $okOwner = { param($o) try { $sid = (New-Object Security.Principal.NTAccount($o)).Translate([Security.Principal.SecurityIdentifier]) } catch { return $false }; $sid -eq $adminSid -or $sid -eq $sysSid -or $sid -eq $id.User }
        if (Test-Path $dir) {
            $di = Get-Item $dir -Force
            if ($di.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-Host "DITOLAK: $dir adalah junction/symlink"; return 2 }
            if (-not (& $okOwner (Get-Acl $dir).Owner)) { Write-Host "DITOLAK: $dir dimiliki $((Get-Acl $dir).Owner), bukan Administrators/SYSTEM"; return 2 }
            # berkas yang SUDAH ada (mis. ditanam user biasa saat folder masih mewarisi ACL ProgramData) tidak dipercaya
            foreach ($fi in @(Get-ChildItem $dir -Force -Recurse)) {
                if ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-Host "DITOLAK: $($fi.FullName) adalah reparse point"; return 2 }
                if (-not (& $okOwner (Get-Acl $fi.FullName).Owner)) { Write-Host "DITOLAK: $($fi.FullName) dimiliki $((Get-Acl $fi.FullName).Owner)"; return 2 }
            }
        } else { New-Item -ItemType Directory $dir | Out-Null }
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetOwner($adminSid); $acl.SetAccessRuleProtection($true, $false)
        foreach ($s in $adminSid, $sysSid) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        }
        Set-Acl $dir $acl
        foreach ($fi in @(Get-ChildItem $dir -Force -File -Recurse)) {   # ACL berkas lama ikut dikunci (Set-Acl folder tak menimpa ACL eksplisit anak)
            $fa = New-Object Security.AccessControl.FileSecurity; $fa.SetOwner($adminSid); $fa.SetAccessRuleProtection($true, $false)
            foreach ($s in $adminSid, $sysSid) { $fa.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($s, 'FullControl', 'Allow'))) }
            Set-Acl $fi.FullName $fa
        }
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
        $tasks = @()
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
                @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableActivityFeed', 0),
                # v5: efek visual Custom = hanya 'thumbnail' + 'font halus' (nilai diambil dari i9 yang sudah diatur manual)
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects', 'VisualFXSetting', 3),
                @('HKCU:\Control Panel\Desktop', 'UserPreferencesMask', [byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0), 'Binary'),
                @('HKCU:\Control Panel\Desktop', 'DragFullWindows', '0', 'String'),
                @('HKCU:\Control Panel\Desktop', 'FontSmoothing', '2', 'String'),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'IconsOnly', 0),
                @('HKCU:\Control Panel\Desktop', 'MenuShowDelay', '0', 'String'),
                @('HKCU:\Control Panel\Desktop\WindowMetrics', 'MinAnimate', '0', 'String'),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarAnimations', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ListviewAlphaSelect', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ListviewShadow', 0),
                @('HKCU:\Software\Microsoft\Windows\DWM', 'EnableAeroPeek', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'EnableTransparency', 0),
                # v5: tips, saran, welcome experience, notifikasi aplikasi startup
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-310093Enabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338388Enabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SoftLandingEnabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement', 'ScoobeSystemSettingEnabled', 0),
                @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.StartupApp', 'Enabled', 0),
                # v5: Fast Startup mati (shutdown = S5 bersih: NTFS tak terkunci untuk Linux, WoL dari S5 konsisten)
                @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', 'HiberbootEnabled', 0),
                # v5: Game Mode ON = bawaan Windows; banyak panduan mematikannya tanpa bukti
                @('HKCU:\Software\Microsoft\GameBar', 'AutoGameModeEnabled', 1)
            )
            foreach ($e in @(Get-Service -Name 'ESRV_SVC*', 'USER_ESRV_SVC*', 'SystemUsageReportSvc_*' -ErrorAction SilentlyContinue)) { $svc[$e.Name] = 'Disabled' }
            $tasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -like 'USER_ESRV_SVC_*' } | ForEach-Object { $_.TaskName })   # Intel SUR: menyalakan esrv di sesi user saat login
            $svc['DSAService'] = 'Disabled'
            $svc['PresentMonSharedService'] = 'Manual'
            # autostart browser: Disabled di StartupApproved (byte pertama 3 = dimatikan user), bukan dihapus dari Run:
            # Chrome/Edge menulis ulang Run, StartupApproved tetap. Yang sudah disabled (byte ganjil) tidak disentuh.
            $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; $saKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            if (Test-Path $runKey) {
                foreach ($n in (Get-Item $runKey).GetValueNames()) {
                    if ($n -notmatch '^(GoogleChromeAutoLaunch_|MicrosoftEdgeAutoLaunch_)') { continue }
                    $cur = $null; if (Test-Path $saKey) { $cur = (Get-Item $saKey).GetValue($n) }   # bukan `$x = if {..}`: itu membongkar byte[]
                    if ($cur -is [byte[]] -and $cur.Length -gt 0 -and ($cur[0] -band 1)) { continue }
                    $reg += , @($saKey, $n, [byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0), 'Binary')
                }
            }
        }
        return @{ reg = $reg; rem = $rem; svc = $svc; tasks = @($tasks) }
    }
    $lists = Get-Lists $Preset
    $reg = $lists.reg; $regRemove = $lists.rem; $svc = $lists.svc; $tasks = $lists.tasks
    $rank = @{ Automatic = 3; Manual = 2; Disabled = 1 }

    function Get-Reg($p, $n) {
        if (-not (Test-Path $p)) { return @{ exists = $false } }
        $k = Get-Item -Path $p
        if ($k.GetValueNames() -notcontains $n) { return @{ exists = $false } }
        return @{ exists = $true; value = $k.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); kind = [string]$k.GetValueKind($n) }
    }
    function Get-Submit { try { (Get-MpPreference).SubmitSamplesConsent } catch { $null } }

    # --- -RemoveApps: daftar default Win11Debloat (github.com/Raphire/Win11Debloat Config/Apps.json, MIT, commit 74be0af),
    #     hanya RemovalMethod=Appx. Tanpa Undo otomatis: pasang ulang lewat Microsoft Store. ---
    $appIds = @(
        'Clipchamp.Clipchamp', 'Microsoft.3DBuilder', 'Microsoft.549981C3F5F10', 'Microsoft.BingFinance',
        'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews', 'Microsoft.BingSports',
        'Microsoft.BingTranslator', 'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.Windows.AIHub',
        'Microsoft.PCManager', 'Microsoft.MicrosoftPCManager', 'Microsoft.Getstarted', 'Microsoft.Messaging',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftJournal', 'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftPowerBIForWindows', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MicrosoftStickyNotes', 'Microsoft.MixedReality.Portal', 'Microsoft.NetworkSpeedTest',
        'Microsoft.Office.OneNote', 'Microsoft.Office.Sway', 'Microsoft.OneConnect', 'Microsoft.Print3D',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.SkypeApp', 'Microsoft.Todos', 'Microsoft.Windows.DevHome',
        'Microsoft.WindowsAlarms', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
        'Microsoft.WindowsSoundRecorder', 'Microsoft.XboxApp', 'Microsoft.ZuneVideo',
        'MicrosoftCorporationII.MicrosoftFamily', 'MicrosoftCorporationII.QuickAssist', 'MicrosoftTeams', 'MSTeams',
        'ACGMediaPlayer', 'ActiproSoftwareLLC', 'AdobeSystemsIncorporated.AdobePhotoshopExpress',
        'Amazon.com.Amazon', 'AmazonVideo.PrimeVideo', 'Asphalt8Airborne', 'AutodeskSketchBook',
        'CaesarsSlotsFreeCasino', 'COOKINGFEVER', 'CyberLinkMediaSuiteEssentials', 'DisneyMagicKingdoms',
        'Disney.37853FC22B2CE', 'DrawboardPDF', 'Duolingo-LearnLanguagesforFree', 'FACEBOOK.FACEBOOK',
        'FarmVille2CountryEscape', 'Flipboard', 'HiddenCity', 'HULULLC.HULUPLUS', 'iHeartRadio',
        'Facebook.Instagram', 'king.com.BubbleWitch3Saga', 'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga',
        'LinkedInforWindows', 'MarchofEmpires', '4DF9E0F8.Netflix', 'NYTCrossword', 'OneCalendar', 'PandoraMediaInc',   # gitleaks:allow (nama paket Store publik, bukan kredensial)
        'PhototasticCollage', 'PicsArt-PhotoStudio', 'PolarrPhotoEditorAcademicEdition',
        'flaregamesGmbH.RoyalRevolt', 'Sidia.LiveWallpaper', 'SlingTV', 'SpotifyAB.SpotifyMusic',
        'BytedancePte.Ltd.TikTok', 'TuneInRadio', 'WinZipUniversal'
    )
    function Remove-Apps([bool]$dry) {
        $f = 0
        try { $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { L "GAGAL membaca daftar provisioned: $($_.Exception.Message)"; return 1 }
        foreach ($a in $appIds) {
            $pk = @(Get-AppxPackage -AllUsers -Name $a -ErrorAction SilentlyContinue); $pv = @($prov | Where-Object { $_.DisplayName -eq $a })
            if ($pk.Count -eq 0 -and $pv.Count -eq 0) { continue }
            if ($dry) { L "aplikasi $a terpasang ($($pk.Count) user, $($pv.Count) provisioned) target=<hapus>"; continue }
            # Remove-AppxPackage -AllUsers bisa ikut mencabut provisioned-nya ("Package was not found" di langkah
            # berikut), jadi sukses/gagal ditentukan dari keadaan AKHIR, bukan dari exception per langkah.
            $err = $null
            foreach ($x in $pk) { try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers } catch { $err = $_.Exception.Message } }
            foreach ($x in $pv) { try { Remove-AppxProvisionedPackage -Online -PackageName $x.PackageName | Out-Null } catch { $err = $_.Exception.Message } }
            try { $left = @(Get-AppxPackage -AllUsers -Name $a -ErrorAction Stop).Count + @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $a }).Count }
            catch { $f++; L "GAGAL verifikasi aplikasi ${a}: keadaan akhir tak terbaca ($($_.Exception.Message))"; continue }
            if ($left -eq 0) { L "aplikasi $a dihapus" } else { $f++; L "GAGAL hapus aplikasi ${a}: masih ada $left (galat terakhir: $err)" }
        }
        return $f
    }

    if ($Mode -eq 'Audit') {
        foreach ($r in $reg) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target={3}" -f $r[0], $r[1], $(if ($g.exists) { "$(@($g.value) -join ',') ($($g.kind))" } else { '<tak ada>' }), (@($r[2]) -join ',')) }
        foreach ($r in $regRemove) { $g = Get-Reg $r[0] $r[1]; L ("reg {0}\{1} sekarang={2} target=<hapus>" -f $r[0], $r[1], $(if ($g.exists) { "$($g.value) ($($g.kind))" } else { '<tak ada>' })) }
        foreach ($k in $svc.Keys) { $s = Get-Service $k -ErrorAction SilentlyContinue; L ("layanan {0} sekarang={1} target={2}" -f $k, $(if ($s) { "$($s.StartType)/$($s.Status)" } else { '<tak ada>' }), $svc[$k]) }
        foreach ($t in $tasks) { $st = (Get-ScheduledTask -TaskPath '\' -TaskName $t -ErrorAction SilentlyContinue).State; L "tugas \$t sekarang=$st target=Disabled" }
        L ("Defender SubmitSamplesConsent sekarang=" + (Get-Submit) + " target=2")
        if ($RemoveApps) { $null = Remove-Apps $true }
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
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; $saKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $uf = 0
        foreach ($r in $u.reg) {
            # HKCU\Run (snapshot v4) TIDAK dipulihkan: isinya perintah yang dijalankan saat login; snapshot bukan sumber perintah tepercaya
            if ($r.path -eq $runKey) { L "dilewati (Run tak dipulihkan; autostart browser bisa dinyalakan lagi lewat Task Manager): $($r.name)"; continue }
            $isRun = ($r.path -eq $saKey -and $r.name -match '^(GoogleChromeAutoLaunch_|MicrosoftEdgeAutoLaunch_)' -and ($r.kind -eq 'Binary' -or -not $r.exists))
            if (-not ($okReg.ContainsKey($r.path + '|' + $r.name) -or $isRun)) { $uf++; L "DITOLAK entri tak dikenal di snapshot: $($r.path)\$($r.name)"; continue }
            try {
                $g = Get-Reg $r.path $r.name
                if (-not $r.exists) {
                    if ($g.exists) { Remove-ItemProperty -Path $r.path -Name $r.name; L "reg $($r.path)\$($r.name) dihapus (semula tak ada)" }
                } elseif ($g.exists -and $g.kind -eq $r.kind -and "$($g.value)" -eq "$($r.value)") { L "reg $($r.path)\$($r.name) sudah $($r.value) ($($r.kind))" }
                else {
                    if (-not (Test-Path $r.path)) { New-Item -Path $r.path -Force | Out-Null }
                    $v = $r.value; if ($r.kind -eq 'Binary') { $v = [byte[]]@($r.value) }
                    New-ItemProperty -Path $r.path -Name $r.name -Value $v -PropertyType $r.kind -Force | Out-Null
                    $g2 = Get-Reg $r.path $r.name
                    if ($g2.exists -and $g2.kind -eq $r.kind -and "$($g2.value)" -eq "$($r.value)") { L "reg $($r.path)\$($r.name) = $($r.value) ($($r.kind))" } else { $uf++; L "GAGAL verifikasi undo reg $($r.path)\$($r.name)" }
                }
            } catch { $uf++; L "GAGAL undo reg $($r.path)\$($r.name): $($_.Exception.Message)" }
        }
        $okKey = @{ $saKey = 1 }; foreach ($r in ($known.reg + $known.rem)) { $okKey[$r[0]] = 1 }
        foreach ($p in @($u.newkeys)) {   # kunci yang DIBUAT Apply: hapus bila kosong (hanya kunci dari daftar skrip ini)
            if (-not $p) { continue }
            if (-not $okKey.ContainsKey($p)) { $uf++; L "DITOLAK kunci tak dikenal di snapshot: $p"; continue }
            try { if ((Test-Path $p) -and -not (Get-Item $p).GetValueNames() -and -not (Get-ChildItem $p)) { Remove-Item $p; L "kunci $p dihapus (dibuat oleh Apply)" } }
            catch { $uf++; L "GAGAL hapus kunci ${p}: $($_.Exception.Message)" }
        }
        foreach ($s in $u.svc) {
            if (-not $okSvc.ContainsKey($s.name) -and $s.name -notmatch '^(ESRV_SVC|USER_ESRV_SVC|SystemUsageReportSvc_)') { $uf++; L "DITOLAK layanan tak dikenal: $($s.name)"; continue }
            try {
                Set-Service -Name $s.name -StartupType $s.old
                $now = (Get-Service $s.name).Status
                if ($s.status -eq 'Running' -and $now -ne 'Running') { Start-Service $s.name }
                if ($s.status -eq 'Stopped' -and $now -eq 'Running') { Stop-Service $s.name -ErrorAction SilentlyContinue }
                $g = Get-Service $s.name
                if ([string]$g.StartType -eq $s.old -and [string]$g.Status -eq $s.status) { L "layanan $($s.name) -> $($s.old)/$($s.status)" }
                else { L "layanan $($s.name) -> $($g.StartType)/$($g.Status) (snapshot $($s.old)/$($s.status); status bisa berubah sendiri oleh trigger)" }
            } catch { $uf++; L "GAGAL undo layanan $($s.name): $($_.Exception.Message)" }
        }
        foreach ($t in @($u.tasks)) {
            if (-not $t -or $t.name -notlike 'USER_ESRV_SVC_*') { if ($t) { $uf++; L "DITOLAK tugas tak dikenal: $($t.name)" }; continue }
            try {
                if ($t.state -eq 'Disabled') { Disable-ScheduledTask -TaskPath '\' -TaskName $t.name | Out-Null } else { Enable-ScheduledTask -TaskPath '\' -TaskName $t.name | Out-Null }
                $now = [string](Get-ScheduledTask -TaskPath '\' -TaskName $t.name).State
                if (($t.state -eq 'Disabled') -eq ($now -eq 'Disabled')) { L "tugas \$($t.name) -> $now" } else { $uf++; L "GAGAL verifikasi tugas $($t.name): $now" }
            }
            catch { $uf++; L "GAGAL undo tugas $($t.name): $($_.Exception.Message)" }
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
    try {
        $owners = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object { $o = Invoke-CimMethod -InputObject $_ -MethodName GetOwner; "$($o.Domain)\$($o.User)" }) | Select-Object -Unique
        if ($owners.Count -gt 0 -and $owners -notcontains $id.Name) { L ("PERINGATAN: desktop yang login milik " + ($owners -join ', ') + ", tetapi skrip berjalan sebagai $($id.Name); setelan HKCU masuk ke akun $($id.Name). Jalankan dari akun desktop itu (Run as administrator).") }
    } catch { }
    if (Test-Path $undof) {
        $old = Get-Content $undof -Raw | ConvertFrom-Json
        if ($old.sid -ne $id.User.Value) { L "DITOLAK: snapshot milik SID $($old.sid), bukan user ini"; return 2 }
        $snap = @{ sid = $old.sid; user = $old.user; reg = @($old.reg); svc = @($old.svc); tasks = @($old.tasks | Where-Object { $_ }); newkeys = @($old.newkeys | Where-Object { $_ }); submit = $old.submit }
        L 'snapshot lama dipertahankan (nilai ASLI pertama); entri baru ditambahkan'
    } else {
        $snap = @{ sid = $id.User.Value; user = $id.Name; reg = @(); svc = @(); tasks = @(); newkeys = @(); submit = (Get-Submit) }
    }
    $seen = @{}; foreach ($e in $snap.reg) { $seen[$e.path + '|' + $e.name] = 1 }
    foreach ($r in ($reg + $regRemove)) {
        if ($seen.ContainsKey($r[0] + '|' + $r[1])) { continue }
        $g = Get-Reg $r[0] $r[1]; $snap.reg += @{ path = $r[0]; name = $r[1]; exists = $g.exists; value = $g.value; kind = $g.kind }
        if (-not (Test-Path $r[0]) -and $snap.newkeys -notcontains $r[0]) { $snap.newkeys += $r[0] }
    }
    $seenS = @{}; foreach ($e in $snap.svc) { $seenS[$e.name] = 1 }
    foreach ($k in $svc.Keys) { if ($seenS.ContainsKey($k)) { continue }; $s = Get-Service $k -ErrorAction SilentlyContinue; if ($s) { $snap.svc += @{ name = $k; old = [string]$s.StartType; status = [string]$s.Status } } }
    $seenT = @{}; foreach ($e in $snap.tasks) { $seenT[$e.name] = 1 }
    foreach ($t in $tasks) { if (-not $seenT.ContainsKey($t)) { $snap.tasks += @{ name = $t; state = [string](Get-ScheduledTask -TaskPath '\' -TaskName $t).State } } }
    $tmp = "$undof.tmp"
    $snap | ConvertTo-Json -Depth 6 | Set-Content $tmp -Encoding UTF8
    $null = Get-Content $tmp -Raw | ConvertFrom-Json   # gagal parse = berhenti sebelum perubahan apa pun
    Move-Item $tmp $undof -Force
    L "snapshot ditulis SEBELUM perubahan: $undof"

    try {
        $before = @(Get-ComputerRestorePoint -ErrorAction Stop).Count
        Checkpoint-Computer -Description 'win-minimal sebelum' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue
        if (@(Get-ComputerRestorePoint).Count -gt $before) { L 'restore point dibuat' } else { L 'restore point tidak dibuat (batas 1/24 jam) - snapshot tetap titik balik' }
    } catch { L 'System Restore tidak aktif / tidak tersedia - dilewati (tidak dinyalakan diam-diam); snapshot tetap titik balik' }

    $fail = 0
    function Test-Same($g, $want, $kind) { $g.exists -and $g.kind -eq $kind -and ((@($g.value) -join ',') -eq (@($want) -join ',')) }
    foreach ($r in $reg) {
        $kind = if ($r.Count -gt 3) { $r[3] } else { 'DWord' }; $show = @($r[2]) -join ','
        $g0 = Get-Reg $r[0] $r[1]
        if (Test-Same $g0 $r[2] $kind) { L ("reg {0}\{1} sudah {2}" -f $r[0], $r[1], $show); continue }
        try {
            if (-not (Test-Path $r[0])) { New-Item -Path $r[0] -Force | Out-Null }
            New-ItemProperty -Path $r[0] -Name $r[1] -Value $r[2] -PropertyType $kind -Force | Out-Null
            if (Test-Same (Get-Reg $r[0] $r[1]) $r[2] $kind) { L ("reg {0}\{1} = {2}" -f $r[0], $r[1], $show) } else { $fail++; L ("GAGAL verifikasi reg {0}\{1}" -f $r[0], $r[1]) }
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
            if ($want -eq 'Disabled') { Stop-Service $k -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }   # tanpa -Force: layanan dependen tidak ikut dihentikan
            Set-Service -Name $k -StartupType $want
            $g = Get-Service $k
            if ([string]$g.StartType -ne $want) { $fail++; L "GAGAL verifikasi layanan $k" }
            elseif ($want -eq 'Disabled' -and $g.Status -ne 'Stopped') { L "layanan $k $cur -> $want (masih $($g.Status) sampai restart)" }
            else { L "layanan $k $cur -> $want" }
        } catch { $fail++; L "GAGAL layanan ${k}: $($_.Exception.Message)" }
    }
    foreach ($t in $tasks) {
        try {
            $st = [string](Get-ScheduledTask -TaskPath '\' -TaskName $t).State
            if ($st -eq 'Disabled') { L "tugas \$t sudah Disabled"; continue }
            Stop-ScheduledTask -TaskPath '\' -TaskName $t -ErrorAction SilentlyContinue
            Disable-ScheduledTask -TaskPath '\' -TaskName $t | Out-Null
            if ([string](Get-ScheduledTask -TaskPath '\' -TaskName $t).State -eq 'Disabled') { L "tugas \$t $st -> Disabled" } else { $fail++; L "GAGAL verifikasi tugas $t" }
        } catch { $fail++; L "GAGAL tugas ${t}: $($_.Exception.Message)" }
    }
    if ($Preset -eq 'Lean') {   # esrv yang sudah terlanjur jalan di sesi user (dari tugas Intel SUR)
        Get-Process esrv -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Intel\SUR\*' } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $left = @(Get-Process esrv -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*\Intel\SUR\*' }).Count
        if ($left -gt 0) { $fail++; L "GAGAL: $left proses esrv Intel SUR masih jalan" } elseif ($tasks.Count -gt 0) { L 'proses esrv Intel SUR tidak berjalan' }
    }
    if ($null -eq $snap.submit) { L 'Defender SubmitSamplesConsent: nilai awal tak terbaca -> tidak diubah (supaya Undo tetap bisa memulihkan)' }
    else { try {
        Set-MpPreference -SubmitSamplesConsent 2
        if ((Get-Submit) -eq 2) { L 'Defender SubmitSamplesConsent = 2 (jangan kirim sampel; real-time tetap ON)' } else { $fail++; L 'GAGAL verifikasi Defender (Tamper Protection?)' }
    } catch { $fail++; L "GAGAL Defender: $($_.Exception.Message)" } }
    if ($RemoveApps) { $fail += Remove-Apps $false }
    L ("APPLY selesai, gagal=$fail. Tanpa restart; sebagian efek (Start, Widgets, aplikasi latar) terasa sesudah sign out / restart.")
    if ($fail -gt 0) { return 1 } else { return 0 }
}

$rc = Invoke-WinMinimal -Mode $Mode -Preset $Preset -RemoveApps:$RemoveApps.IsPresent
if ($PSCommandPath) { exit $rc }   # sebagai berkas: kembalikan exit code; lewat irm|iex: jangan tutup jendela pengguna
