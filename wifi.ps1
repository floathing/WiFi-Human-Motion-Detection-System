# =====================================================================
#  wifi_guardian_dashboard.ps1
#  Live WiFi motion dashboard in your BROWSER. Laptop + WiFi only.
#  No ESP32, no install, no Python. Pure PowerShell + your browser.
# =====================================================================
#  RUN:
#     powershell -ExecutionPolicy Bypass -File "$HOME\Desktop\wifi_guardian_dashboard.ps1"
#  Then open this in your browser:
#     http://localhost:8080
#
#  Keep the area EMPTY for the 15s calibration, then have someone walk
#  the path between the laptop and the router. The page shows a live room
#  diagram: ALL CLEAR (blue beam) flips to MOTION (red beam + figure).
#  Press Ctrl+C in this window to stop.
#
#  TUNE: -Sensitivity 1.8 (more sensitive) | -Sensitivity 3.0 -Floor 2.5 (calmer)
#  Your own WiFi / your own space / consent only.
# =====================================================================

param(
  [double]$Window      = 3.0,
  [double]$Calibrate   = 15.0,
  [double]$Sensitivity = 2.5,
  [double]$Floor       = 1.5,
  [double]$HoldSeconds = 3.0,
  [int]$Port           = 8080
)

function Get-Signal {
  $out = (netsh wlan show interfaces) -join "`n"
  $m = [regex]::Match($out, 'Signal\s*:\s*(\d+)\s*%')
  if ($m.Success) { return [double]$m.Groups[1].Value }
  return $null
}
function Get-Std($vals) {
  $arr = @($vals); $n = $arr.Count
  if ($n -lt 2) { return 0.0 }
  $mean = ($arr | Measure-Object -Average).Average
  $sum = 0.0; foreach ($v in $arr) { $sum += [math]::Pow($v - $mean, 2) }
  return [math]::Sqrt($sum / $n)
}

$html = @'
<!doctype html><html><head><meta charset="utf-8"><title>WiFi Guardian</title>
<style>
 body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#0f172a;color:#e2e8f0;}
 .wrap{max-width:680px;margin:0 auto;padding:24px;}
 .badge{display:inline-block;padding:8px 18px;border-radius:999px;font-weight:700;font-size:16px;}
 .clear{background:#064e3b;color:#6ee7b7;} .motion{background:#7f1d1d;color:#fca5a5;}
 .card{background:#1e293b;border-radius:14px;padding:18px;margin-top:14px;}
 .stat{display:flex;gap:12px;flex-wrap:wrap;margin-top:14px;}
 .stat>div{background:#1e293b;border-radius:10px;padding:10px 16px;font-size:13px;color:#94a3b8;flex:1;min-width:120px;}
 .big{font-size:22px;font-weight:700;color:#e2e8f0;}
 svg{width:100%;height:auto;background:#0b1220;border-radius:12px;}
 .bar{height:14px;background:#0b1220;border-radius:999px;overflow:hidden;}
 .fill{height:100%;width:4%;background:#34d399;border-radius:999px;transition:width .15s,background .15s;}
 .muted{color:#94a3b8;font-size:13px;line-height:1.6;}
</style></head>
<body><div class="wrap">
 <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">
  <div style="font-size:24px;font-weight:700;">WiFi Guardian</div>
  <div id="badge" class="badge clear">&#9679; ALL CLEAR</div>
 </div>
 <div id="calib" class="card" style="text-align:center;">Calibrating&hellip; keep the area empty &nbsp;<b><span id="cd"></span></b></div>
 <div class="card">
  <svg viewBox="0 0 520 280">
   <rect x="20" y="20" width="480" height="240" rx="10" fill="none" stroke="#334155" stroke-width="1.5"/>
   <line id="beam" x1="70" y1="75" x2="450" y2="215" stroke="#3b82f6" stroke-width="2.5" stroke-dasharray="7 6"/>
   <rect x="48" y="55" width="44" height="30" rx="6" fill="#14b8a6"/>
   <text x="70" y="100" text-anchor="middle" font-size="12" fill="#94a3b8">Router</text>
   <rect x="428" y="201" width="44" height="26" rx="3" fill="#8b5cf6"/>
   <text x="450" y="247" text-anchor="middle" font-size="12" fill="#94a3b8">Laptop</text>
   <g id="person" style="opacity:0;transition:opacity .25s;">
     <circle cx="260" cy="131" r="8" fill="#ef4444"/>
     <rect x="252" y="140" width="16" height="24" rx="7" fill="#ef4444"/>
   </g>
  </svg>
 </div>
 <div class="stat">
  <div>Signal<br><span id="sig" class="big">--</span>%</div>
  <div>Wobble<br><span id="wob" class="big">--</span></div>
  <div>Last motion<br><span id="lm" class="big">--</span></div>
  <div>Alerts<br><span id="al" class="big">0</span></div>
 </div>
 <div class="card">
  <div class="muted" style="margin-bottom:6px;">Live signal wobble</div>
  <div class="bar"><div id="fill" class="fill"></div></div>
 </div>
 <div class="muted" style="margin-top:12px;">Shows motion on the WiFi line between your router and laptop. One link = &ldquo;something crossed the beam&rdquo; &mdash; not exact position or body shape.</div>
</div>
<script>
 async function tick(){
  try{
   const r=await fetch('/status'); const s=await r.json();
   const calib=document.getElementById('calib');
   if(s.calibrating){calib.style.display='block';document.getElementById('cd').textContent=s.secsLeft+'s';}
   else{calib.style.display='none';}
   document.getElementById('sig').textContent=Math.round(s.signal);
   document.getElementById('wob').textContent=Number(s.wobble).toFixed(2);
   document.getElementById('lm').textContent=s.lastMotion;
   document.getElementById('al').textContent=s.alerts;
   const badge=document.getElementById('badge'),beam=document.getElementById('beam'),
         person=document.getElementById('person'),fill=document.getElementById('fill');
   let lvl=s.threshold>0?Math.min(1,s.wobble/(s.threshold*1.4)):0;
   fill.style.width=(Math.max(4,lvl*100))+'%';
   if(s.motion){
     badge.className='badge motion';badge.innerHTML='&#9679; MOTION DETECTED';
     beam.setAttribute('stroke','#ef4444');person.style.opacity=1;fill.style.background='#f87171';
   }else{
     badge.className='badge clear';badge.innerHTML='&#9679; ALL CLEAR';
     beam.setAttribute('stroke','#3b82f6');person.style.opacity=0;fill.style.background='#34d399';
   }
  }catch(e){}
 }
 setInterval(tick,400);tick();
</script></body></html>
'@

# ---- start the local web server ----
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() }
catch {
  Write-Host "Could not start the server on port $Port." -ForegroundColor Yellow
  Write-Host "Tip: run PowerShell as Administrator, or try a different -Port." -ForegroundColor Yellow
  exit
}
Write-Host ""
Write-Host "  WiFi Guardian dashboard is running." -ForegroundColor Green
Write-Host "  >>> Open this in your browser:  http://localhost:$Port" -ForegroundColor Cyan
Write-Host "  (Keep the area empty for $Calibrate s while it calibrates.)" -ForegroundColor Gray
Write-Host "  Press Ctrl+C here to stop." -ForegroundColor Gray
Write-Host ""

# ---- sensing state ----
$samples         = New-Object System.Collections.Generic.List[object]
$baselineSamples = New-Object System.Collections.Generic.List[double]
$start           = Get-Date
$calibrating     = $true
$baseline        = 0.0
$threshold       = 0.0
$lastMotionTime  = $null
$alertCount      = 0
$inMotion        = $false

$state = @{ signal=0.0; wobble=0.0; lastMotion='-- none --'; alerts=0;
           calibrating=$true; secsLeft=[int]$Calibrate; motion=$false; threshold=0.0 }

$task = $listener.GetContextAsync()

while ($true) {
  $now = Get-Date
  $sig = Get-Signal
  if ($null -ne $sig) {
    $samples.Add([pscustomobject]@{ t = $now; v = $sig })
    while ($samples.Count -gt 0 -and ($now - $samples[0].t).TotalSeconds -gt $Window) {
      $samples.RemoveAt(0)
    }
    $wobble = Get-Std (@($samples | ForEach-Object { $_.v }))

    if ($calibrating) {
      if ($samples.Count -ge 3) { $baselineSamples.Add($wobble) }
      $left = [int][math]::Ceiling($Calibrate - ($now - $start).TotalSeconds)
      if ($left -lt 0) { $left = 0 }
      $state.secsLeft = $left
      if (($now - $start).TotalSeconds -ge $Calibrate) {
        if ($baselineSamples.Count -gt 0) {
          $baseline = ($baselineSamples | Measure-Object -Average).Average
        }
        $threshold = [math]::Max($baseline * $Sensitivity, $baseline + $Floor)
        $calibrating = $false
        $state.threshold = $threshold
        Write-Host "  [+] Calibrated. Watching for motion..." -ForegroundColor Green
      }
    }
    else {
      $moving = $wobble -gt $threshold
      if ($moving) {
        $lastMotionTime = $now
        if (-not $inMotion) { $inMotion = $true; $alertCount++; [console]::beep(1000,200) }
      }
      elseif ($inMotion -and $lastMotionTime -and ($now - $lastMotionTime).TotalSeconds -gt $HoldSeconds) {
        $inMotion = $false
      }
      $state.motion = $inMotion
    }

    $state.signal      = $sig
    $state.wobble      = [math]::Round($wobble, 2)
    $state.calibrating = $calibrating
    $state.alerts      = $alertCount
    if ($lastMotionTime) { $state.lastMotion = $lastMotionTime.ToString("HH:mm:ss") }
  }

  # ---- serve any pending browser request ----
  if ($task.IsCompleted) {
    try {
      $ctx  = $task.Result
      $path = $ctx.Request.Url.AbsolutePath
      if ($path -eq '/status') {
        $payload = ($state | ConvertTo-Json -Compress)
        $ctx.Response.ContentType = 'application/json'
      } else {
        $payload = $html
        $ctx.Response.ContentType = 'text/html'
      }
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $ctx.Response.OutputStream.Close()
    } catch {}
    $task = $listener.GetContextAsync()
  }

  Start-Sleep -Milliseconds 120
}