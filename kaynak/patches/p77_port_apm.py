# -*- coding: utf-8 -*-
"""p77: port yoklamasi TcpClient.ConnectAsync yerine BeginConnect (APM) kullanir.
Gercek bilgisayarda (18.11.2026, salt okuma denetimi) port taramasindan sonra 20 "gozlenmeyen gorev hatasi" goruldu:
ConnectAsync gorevi sure dolup istemci kapatildiktan sonra TcpClient.EndConnect icinde NullReferenceException ile
sonuclaniyor, kimse beklemedigi icin sonlandirici is parcacigi hatayi yeniden firlatiyordu. APM'de suresi dolan
baglanti icin EndConnect cagrilmaz; tamamlanan baglantida EndConnect try icinde cagrilir. Sonuc ayni (acik portlar)."""


def apply(b):
    b.rep("""        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $t = $c.ConnectAsync($ip, [int]$k)
            if ($t.Wait(350) -and $c.Connected) { [void]$open.Add(@{ Port = [int]$k; Name = [string]$script:CommonPorts[$k] }) }
        } catch { } finally { try { $c.Close() } catch { } }
""", """        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $iar = $c.BeginConnect($ip, [int]$k, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(350, $false)) {
                try { $c.EndConnect($iar) } catch { }
                if ($c.Connected) { [void]$open.Add(@{ Port = [int]$k; Name = [string]$script:CommonPorts[$k] }) }
            }
        } catch { } finally { try { $c.Close() } catch { } }
""", name='p77 port denetimi APM')
    b.rep("""        $cl = New-Object System.Collections.ArrayList
        $tk = New-Object System.Collections.ArrayList
        for ($k = $i; $k -le $end; $k++) {
            try {
                $c = New-Object System.Net.Sockets.TcpClient
                [void]$cl.Add($c)
                [void]$tk.Add($c.ConnectAsync($jobs[$k].Ip, $jobs[$k].Port))
            } catch { [void]$cl.Add($null); [void]$tk.Add($null) }
        }
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tk | Where-Object { $null -ne $_ }), $TimeoutMs) } catch { }
        for ($k = 0; $k -lt $tk.Count; $k++) {
            $c = $cl[$k]; $t = $tk[$k]
            if ($null -eq $c -or $null -eq $t) { continue }
            try {
                if ($t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and $c.Connected) {
                    $j = $jobs[$i + $k]
                    if (-not $res.ContainsKey($j.Ip)) { $res[$j.Ip] = New-Object System.Collections.ArrayList }
                    [void]$res[$j.Ip].Add([int]$j.Port)
                }
            } catch { }
        }
""", """        $cl = New-Object System.Collections.ArrayList
        $ia = New-Object System.Collections.ArrayList
        for ($k = $i; $k -le $end; $k++) {
            try {
                $c = New-Object System.Net.Sockets.TcpClient
                [void]$cl.Add($c)
                [void]$ia.Add($c.BeginConnect($jobs[$k].Ip, $jobs[$k].Port, $null, $null))
            } catch { [void]$cl.Add($null); [void]$ia.Add($null) }
        }
        # tek ortak sure: her baglanti, partinin kalan suresi kadar beklenir
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($k = 0; $k -lt $ia.Count; $k++) {
            $c = $cl[$k]; $r = $ia[$k]
            if ($null -eq $c -or $null -eq $r) { continue }
            try {
                $left = [int]($TimeoutMs - $sw.ElapsedMilliseconds)
                if ($left -lt 0) { $left = 0 }
                if ($r.AsyncWaitHandle.WaitOne($left, $false)) {
                    try { $c.EndConnect($r) } catch { }
                    if ($c.Connected) {
                        $j = $jobs[$i + $k]
                        if (-not $res.ContainsKey($j.Ip)) { $res[$j.Ip] = New-Object System.Collections.ArrayList }
                        [void]$res[$j.Ip].Add([int]$j.Port)
                    }
                }
            } catch { }
        }
""", name='p77 port yoklamasi APM')
