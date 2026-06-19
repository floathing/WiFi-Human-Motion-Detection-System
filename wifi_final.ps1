# =====================================================================
#  wifi_guardian_pro2.ps1  -  WiFi Guardian Pro v2 (Windows, laptop+WiFi only)
# =====================================================================
#  New in v2:
#    * Live wobble HISTORY GRAPH (last ~45s)
#    * Live SENSITIVITY / CONFIRM / FLOOR sliders (no restart needed)
#    * Motion EVENT LOG with timestamps + duration
#    * Polished redesign + pulsing beam
#    * Honest LOCATION panel (one link can't pinpoint - shows upgrade path)
#  Keeps: adaptive baseline, hysteresis, noise filter, anti-false-alarm.
#
#  RUN:  powershell -ExecutionPolicy Bypass -File "$HOME\Desktop\wifi_guardian_pro2.ps1"
#  OPEN: http://localhost:8080   (keep area empty for calibration; Ctrl+C to stop)
#  Your own WiFi / your own space / consent only.
# =====================================================================

param(
  [double]$Window      = 3.0,
  [double]$Calibrate   = 20.0,
  [double]$Sensitivity = 2.5,
  [double]$Floor       = 1.0,
  [double]$ClearFactor = 0.5,
  [int]   $Confirm     = 3,
  [double]$HoldSeconds = 3.0,
  [double]$Adapt       = 0.02,
  [double]$SmoothAlpha = 0.4,
  [double]$OutlierJump = 25.0,
  [int]   $Port        = 8080
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
function Get-Median($vals) {
  $a = @($vals | Sort-Object); $n = $a.Count
  if ($n -eq 0) { return $null }
  if ($n % 2) { return [double]$a[[int](($n - 1) / 2)] }
  return ([double]$a[$n/2 - 1] + [double]$a[$n/2]) / 2.0
}

$html = @'
<!doctype html><html><head><meta charset="utf-8"><title>WiFi Guardian Pro</title>
<style>
 :root{--bg:#0b1220;--card:#161f33;--card2:#1e293b;--txt:#e2e8f0;--mut:#94a3b8;--accent:#38bdf8;}
 *{box-sizing:border-box;}
 body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:linear-gradient(160deg,#0b1220,#0f172a);color:var(--txt);}
 .wrap{max-width:760px;margin:0 auto;padding:24px;}
 .top{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;}
 .title{font-size:26px;font-weight:800;letter-spacing:.3px;}
 .title span{color:var(--accent);}
 .badge{display:inline-block;padding:9px 20px;border-radius:999px;font-weight:700;font-size:16px;}
 .clear{background:#064e3b;color:#6ee7b7;} .motion{background:#7f1d1d;color:#fca5a5;box-shadow:0 0 0 0 rgba(239,68,68,.6);animation:glow 1.2s infinite;}
 @keyframes glow{0%{box-shadow:0 0 0 0 rgba(239,68,68,.5);}70%{box-shadow:0 0 0 12px rgba(239,68,68,0);}100%{box-shadow:0 0 0 0 rgba(239,68,68,0);}}
 .tags{margin-top:8px;} .tag{display:inline-block;background:#0b1220;color:#7dd3fc;font-size:11px;padding:3px 9px;border-radius:6px;margin:0 6px 6px 0;border:1px solid #1e3a5f;}
 .card{background:var(--card);border:1px solid #223049;border-radius:16px;padding:18px;margin-top:14px;}
 .calib{text-align:center;background:#13233f;border-color:#1e3a5f;}
 .stat{display:flex;gap:12px;flex-wrap:wrap;margin-top:14px;}
 .stat>div{background:var(--card2);border-radius:12px;padding:12px 16px;font-size:13px;color:var(--mut);flex:1;min-width:110px;}
 .big{font-size:23px;font-weight:800;color:var(--txt);}
 svg{width:100%;height:auto;background:#0a1018;border-radius:12px;}
 .beam{transition:stroke .2s;} .beam.on{animation:dash 1s linear infinite;}
 @keyframes dash{to{stroke-dashoffset:-26;}}
 .bar{height:14px;background:#0a1018;border-radius:999px;overflow:hidden;}
 .fill{height:100%;width:4%;background:#34d399;border-radius:999px;transition:width .15s,background .15s;}
 .muted{color:var(--mut);font-size:13px;line-height:1.6;}
 canvas{width:100%;height:150px;display:block;}
 .ctl{display:flex;align-items:center;gap:12px;margin:10px 0;}
 .ctl label{flex:0 0 170px;font-size:13px;color:var(--mut);}
 .ctl input[type=range]{flex:1;accent-color:var(--accent);}
 .ctl b{color:var(--accent);}
 .ev{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #223049;font-size:14px;}
 .ev:last-child{border-bottom:none;}
 .loc{background:#13233f;border:1px dashed #2b4a73;}
</style></head>
<body><div class="wrap">
 <div class="top">
  <div class="title">WiFi Guardian <span>Pro</span></div>
  <div id="badge" class="badge clear">&#9679; ALL CLEAR</div>
 </div>
 <div class="tags">
  <span class="tag">adaptive baseline</span><span class="tag">hysteresis</span><span class="tag">noise filter</span><span class="tag">anti false-alarm</span><span class="tag">live tuning</span>
 </div>

 <div id="calib" class="card calib">Calibrating&hellip; keep the area empty &nbsp;<b><span id="cd"></span></b></div>

 <div class="card">
  <svg viewBox="0 0 520 280">
   <rect x="20" y="20" width="480" height="240" rx="10" fill="none" stroke="#2a3a55" stroke-width="1.5"/>
   <line id="beam" class="beam" x1="70" y1="75" x2="450" y2="215" stroke="#3b82f6" stroke-width="2.5" stroke-dasharray="7 6"/>
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
  <div class="muted" style="margin-bottom:8px;">Signal wobble &mdash; live (last ~45s)</div>
  <canvas id="g"></canvas>
  <div class="bar" style="margin-top:10px;"><div id="fill" class="fill"></div></div>
  <div class="muted" id="lvls" style="margin-top:8px;"></div>
 </div>

 <div class="card">
  <div class="muted" style="margin-bottom:6px;">Live controls &mdash; tune without restarting</div>
  <div class="ctl"><label>Sensitivity (lower = more) <b id="sv">2.5</b></label><input id="s_sens" type="range" min="1.2" max="4" step="0.1" value="2.5"></div>
  <div class="ctl"><label>Confirm readings <b id="cv">3</b></label><input id="s_conf" type="range" min="1" max="6" step="1" value="3"></div>
  <div class="ctl"><label>Floor <b id="fv">1.0</b></label><input id="s_floor" type="range" min="0.3" max="3" step="0.1" value="1.0"></div>
 </div>

 <div class="card">
  <div class="muted" style="margin-bottom:8px;">Recent motion events</div>
  <div id="log" class="muted">No events yet.</div>
 </div>

 <div class="card loc">
  <div style="font-weight:700;margin-bottom:4px;">Location: <span style="color:#fca5a5;">somewhere on the router&ndash;laptop line</span></div>
  <div class="muted">A single WiFi link can't pinpoint <i>where</i> in the room. To map zones, add more sensor links (e.g. several ESP32 nodes) and the system can triangulate which area moved.</div>
 </div>
</div>
<script>
 var hist=[]; var MAXH=120;
 function drawGraph(trigger){
  var c=document.getElementById('g'); var ctx=c.getContext('2d');
  var w=c.width=c.clientWidth*window.devicePixelRatio; var h=c.height=150*window.devicePixelRatio;
  ctx.scale(1,1); ctx.clearRect(0,0,w,h);
  var mx=2; for(var i=0;i<hist.length;i++){if(hist[i]>mx)mx=hist[i];} mx=Math.max(mx,trigger*1.5,2);
  // trigger line
  var ty=h-(trigger/mx)*h;
  ctx.strokeStyle='#f87171';ctx.setLineDash([5,5]);ctx.lineWidth=1*window.devicePixelRatio;
  ctx.beginPath();ctx.moveTo(0,ty);ctx.lineTo(w,ty);ctx.stroke();ctx.setLineDash([]);
  // wobble line
  ctx.strokeStyle='#38bdf8';ctx.lineWidth=2*window.devicePixelRatio;ctx.beginPath();
  for(var j=0;j<hist.length;j++){
   var x=(j/(MAXH-1))*w; var y=h-(hist[j]/mx)*h;
   if(j===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);
  }
  ctx.stroke();
 }
 function renderLog(events){
  var el=document.getElementById('log');
  if(events&&!Array.isArray(events))events=[events];
  if(!events||events.length===0){el.innerHTML='No events yet.';return;}
  var h='';
  for(var i=0;i<events.length;i++){
   h+='<div class="ev"><span>&#9679; Motion '+events[i].time+'</span><span style="color:#94a3b8;">lasted '+events[i].dur+'s</span></div>';
  }
  el.innerHTML=h;
 }
 async function tick(){
  try{
   var r=await fetch('/status'); var s=await r.json();
   var calib=document.getElementById('calib');
   if(s.calibrating){calib.style.display='block';document.getElementById('cd').textContent=s.secsLeft+'s';}
   else{calib.style.display='none';}
   document.getElementById('sig').textContent=Math.round(s.signal);
   document.getElementById('wob').textContent=Number(s.wobble).toFixed(2);
   document.getElementById('lm').textContent=s.lastMotion;
   document.getElementById('al').textContent=s.alerts;
   document.getElementById('lvls').innerHTML='baseline <b>'+Number(s.baseline).toFixed(2)+'</b> &nbsp;|&nbsp; trigger <b>'+Number(s.trigger).toFixed(2)+'</b> &nbsp;|&nbsp; clear <b>'+Number(s.clear).toFixed(2)+'</b>';
   hist.push(Number(s.wobble)); if(hist.length>MAXH)hist.shift();
   drawGraph(Number(s.trigger));
   renderLog(s.events);
   var badge=document.getElementById('badge'),beam=document.getElementById('beam'),
       person=document.getElementById('person'),fill=document.getElementById('fill');
   var lvl=s.trigger>0?Math.min(1,s.wobble/(s.trigger*1.4)):0;
   fill.style.width=(Math.max(4,lvl*100))+'%';
   if(s.motion){
     badge.className='badge motion';badge.innerHTML='&#9679; MOTION DETECTED';
     beam.setAttribute('stroke','#ef4444');beam.classList.add('on');person.style.opacity=1;fill.style.background='#f87171';
   }else{
     badge.className='badge clear';badge.innerHTML='&#9679; ALL CLEAR';
     beam.setAttribute('stroke','#3b82f6');beam.classList.remove('on');person.style.opacity=0;fill.style.background='#34d399';
   }
  }catch(e){}
 }
 function bind(id,lbl,key){
  var el=document.getElementById(id),out=document.getElementById(lbl);
  el.addEventListener('input',function(){
   out.textContent=el.value; clearTimeout(el._t);
   el._t=setTimeout(function(){fetch('/set?'+key+'='+el.value);},150);
  });
 }
 bind('s_sens','sv','sensitivity');bind('s_conf','cv','confirm');bind('s_floor','fv','floor');
 setInterval(tick,350);tick();
</script></body></html>
'@

# ---- start local web server ----
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() }
catch { Write-Host "Could not start server on port $Port. Run as Administrator or try another -Port." -ForegroundColor Yellow; exit }
Write-Host ""
Write-Host "  WiFi Guardian PRO v2 is running." -ForegroundColor Green
Write-Host "  >>> Open in your browser:  http://localhost:$Port" -ForegroundColor Cyan
Write-Host "  Keep the area empty for $Calibrate s. Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

# ---- sensing state ----
$samples         = New-Object System.Collections.Generic.List[object]
$recentRaw       = New-Object System.Collections.Generic.List[double]
$baselineSamples = New-Object System.Collections.Generic.List[double]
$events          = @()
$start           = Get-Date
$calibrating     = $true
$baseline        = 0.0
$trigger         = 0.0
$clear           = 0.0
$wobbleEma       = 0.0
$consec          = 0
$lastMotionTime  = $null
$motionStart     = $null
$alertCount      = 0
$inMotion        = $false

$state = @{ signal=0.0; wobble=0.0; baseline=0.0; trigger=0.0; clear=0.0;
           lastMotion='-- none --'; alerts=0; calibrating=$true;
           secsLeft=[int]$Calibrate; motion=$false; events=@() }

$task = $listener.GetContextAsync()

while ($true) {
  $now = Get-Date
  $raw = Get-Signal
  if ($null -ne $raw) {
    $accept = $true
    if ($recentRaw.Count -ge 3) {
      $med = Get-Median $recentRaw
      if ([math]::Abs($raw - $med) -gt $OutlierJump) { $accept = $false }
    }
    $recentRaw.Add($raw); while ($recentRaw.Count -gt 5) { $recentRaw.RemoveAt(0) }

    if ($accept) {
      $samples.Add([pscustomobject]@{ t = $now; v = $raw })
      while ($samples.Count -gt 0 -and ($now - $samples[0].t).TotalSeconds -gt $Window) { $samples.RemoveAt(0) }

      $rawWobble = Get-Std (@($samples | ForEach-Object { $_.v }))
      $wobbleEma = $SmoothAlpha * $rawWobble + (1 - $SmoothAlpha) * $wobbleEma
      $wobble = $wobbleEma

      if ($calibrating) {
        if ($samples.Count -ge 3) { $baselineSamples.Add($wobble) }
        $left = [int][math]::Ceiling($Calibrate - ($now - $start).TotalSeconds); if ($left -lt 0) { $left = 0 }
        $state.secsLeft = $left
        if (($now - $start).TotalSeconds -ge $Calibrate) {
          if ($baselineSamples.Count -gt 0) { $baseline = ($baselineSamples | Measure-Object -Average).Average }
          $calibrating = $false
          Write-Host "  [+] Calibrated. Watching (adaptive)..." -ForegroundColor Green
        }
      }
      else {
        $trigger = [math]::Max($baseline * $Sensitivity, $baseline + $Floor)
        $clear   = $trigger * $ClearFactor
        if (-not $inMotion) {
          if ($wobble -gt $trigger) { $consec++ } else { $consec = 0 }
          if ($consec -ge $Confirm) {
            $inMotion = $true; $alertCount++; $motionStart = $now; $lastMotionTime = $now
            [console]::beep(1000, 180)
          }
          if ($wobble -lt $trigger) { $baseline = $baseline + $Adapt * ($wobble - $baseline); if ($baseline -lt 0) { $baseline = 0 } }
        }
        else {
          if ($wobble -gt $clear) { $lastMotionTime = $now }
          if ($lastMotionTime -and ($now - $lastMotionTime).TotalSeconds -gt $HoldSeconds -and $wobble -lt $clear) {
            $inMotion = $false; $consec = 0
            $dur = [int]($now - $motionStart).TotalSeconds
            $events = @([pscustomobject]@{ time = $motionStart.ToString("HH:mm:ss"); dur = $dur }) + $events
            if ($events.Count -gt 8) { $events = @($events[0..7]) }
          }
        }
        $state.motion = $inMotion
      }

      $state.signal      = $raw
      $state.wobble      = [math]::Round($wobble, 2)
      $state.baseline    = [math]::Round($baseline, 2)
      $state.trigger     = [math]::Round($trigger, 2)
      $state.clear       = [math]::Round($clear, 2)
      $state.calibrating = $calibrating
      $state.alerts      = $alertCount
      $state.events      = $events
      if ($lastMotionTime) { $state.lastMotion = $lastMotionTime.ToString("HH:mm:ss") }
    }
  }

  # ---- serve browser requests ----
  if ($task.IsCompleted) {
    try {
      $ctx  = $task.Result
      $path = $ctx.Request.Url.AbsolutePath
      if ($path -eq '/status') {
        $payload = ($state | ConvertTo-Json -Depth 5 -Compress)
        $ctx.Response.ContentType = 'application/json'
      }
      elseif ($path -eq '/set') {
        $qs = $ctx.Request.QueryString
        if ($qs['sensitivity']) { $Sensitivity = [double]$qs['sensitivity'] }
        if ($qs['confirm'])     { $Confirm     = [int]$qs['confirm'] }
        if ($qs['floor'])       { $Floor       = [double]$qs['floor'] }
        $payload = '{"ok":true}'
        $ctx.Response.ContentType = 'application/json'
      }
      else {
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