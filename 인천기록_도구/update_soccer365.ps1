param(
    [switch]$SkipExcel,
    [switch]$ApplyExistingData
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$toolDir = $PSScriptRoot
$rootDir = Split-Path -Parent $toolDir
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$configPath = Join-Path $toolDir "soccer365_config.json"
$config = [System.IO.File]::ReadAllText($configPath, $utf8NoBom) | ConvertFrom-Json

$workbookPath = Join-Path $rootDir $config.paths.workbook
$dashboardPath = Join-Path $rootDir $config.paths.dashboard
$indexPath = Join-Path $rootDir "index.html"
$templatePath = Join-Path $toolDir "template.html"
$dataPath = Join-Path $toolDir "data.json"
$leagueResultsPath = Join-Path $toolDir "league_results.json"
$snapshotPath = Join-Path $toolDir "soccer365_snapshot.json"

$competitionUrl = "https://soccer365.net/competitions/$($config.competition_id)/"
$resultsUrl = "${competitionUrl}results/"
$scheduleUrl = "${competitionUrl}shedule/"
$clubPlayersUrl = "https://soccer365.net/clubs/$($config.club_id)/&tab=players"

function Read-Utf8Json([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return ([System.IO.File]::ReadAllText($path, $utf8NoBom) | ConvertFrom-Json)
}

function Write-Utf8([string]$path, [string]$text) {
    [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Convert-ObjectToMap($obj) {
    $map = @{}
    if ($null -eq $obj) { return $map }
    foreach ($p in $obj.PSObject.Properties) { $map[[string]$p.Name] = $p.Value }
    return $map
}

$teamMap = Convert-ObjectToMap $config.teams
$playerIdMap = Convert-ObjectToMap $config.players_by_id
$playerAliasMap = Convert-ObjectToMap $config.player_aliases
$refereeAliasMap = Convert-ObjectToMap $config.referee_aliases
$unknownNames = New-Object System.Collections.Generic.HashSet[string]

function Convert-TeamName([string]$name) {
    if ($teamMap.ContainsKey($name)) { return [string]$teamMap[$name] }
    throw "Unknown Soccer365 team name: $name"
}

function Convert-PlayerName([string]$name, [string]$id = "") {
    $clean = ($name -replace "\s+", " ").Trim()
    if ($id -and $playerIdMap.ContainsKey($id)) { return [string]$playerIdMap[$id] }
    if ($playerAliasMap.ContainsKey($clean)) { return [string]$playerAliasMap[$clean] }
    if ($clean) { [void]$unknownNames.Add($clean) }
    return $clean
}

function Convert-RefereeName([string]$name) {
    $clean = ($name -replace "\s+", " ").Trim()
    if ($refereeAliasMap.ContainsKey($clean)) { return [string]$refereeAliasMap[$clean] }
    return $clean
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Find-BrowserExecutable {
    $candidates = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "Chrome or Microsoft Edge is required for Soccer365 collection."
}

$browserProcess = $null
$browserProfile = $null
$cdpSocket = $null
$cdpId = 0
$cdpToken = [System.Threading.CancellationToken]::None

function Start-SoccerBrowser {
    $browserExe = Find-BrowserExecutable
    $port = Get-FreeTcpPort
    $browserProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("incheon-s365-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Force -Path $browserProfile)

    $args = @(
        "--remote-debugging-port=$port",
        "--remote-allow-origins=*",
        "--disable-extensions",
        "--disable-sync",
        "--disable-blink-features=AutomationControlled",
        "--no-first-run",
        "--no-default-browser-check",
        "--window-position=-32000,-32000",
        "--window-size=1280,900",
        "--user-data-dir=$browserProfile",
        $resultsUrl
    )

    $browserProcess = Start-Process -FilePath $browserExe -ArgumentList $args -PassThru -WindowStyle Hidden
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    $page = $null
    do {
        Start-Sleep -Milliseconds 500
        try {
            $tabs = Invoke-RestMethod "http://127.0.0.1:$port/json/list" -TimeoutSec 2
            $page = $tabs | Where-Object { $_.type -eq "page" } | Select-Object -First 1
        } catch { $page = $null }
    } while ((-not $page.webSocketDebuggerUrl) -and [DateTime]::UtcNow -lt $deadline)

    if (-not $page.webSocketDebuggerUrl) { throw "Could not connect to the local browser."
    }

    $cdpSocket = New-Object System.Net.WebSockets.ClientWebSocket
    [void]$cdpSocket.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cdpToken).GetAwaiter().GetResult()
    [void](Invoke-Cdp "Page.enable" @{})

    $script:browserProcess = $browserProcess
    $script:browserProfile = $browserProfile
    $script:cdpSocket = $cdpSocket
}

function Invoke-Cdp([string]$method, $params) {
    $script:cdpId += 1
    $requestId = $script:cdpId
    $message = @{ id = $requestId; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 50
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (,$bytes)
    [void]$cdpSocket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cdpToken).GetAwaiter().GetResult()

    while ($true) {
        $stream = New-Object System.IO.MemoryStream
        do {
            $buffer = New-Object byte[] 65536
            $receiveSegment = New-Object System.ArraySegment[byte] -ArgumentList (,$buffer)
            $received = $cdpSocket.ReceiveAsync($receiveSegment, $cdpToken).GetAwaiter().GetResult()
            if ($received.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "The local browser connection closed unexpectedly."
            }
            $stream.Write($buffer, 0, $received.Count)
        } while (-not $received.EndOfMessage)

        $text = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
        $response = $text | ConvertFrom-Json
        if ($response.id -eq $requestId) {
            if ($response.error) { throw "Browser command failed: $($response.error.message)" }
            return $response.result
        }
    }
}

function Invoke-PageScript([string]$expression) {
    $result = Invoke-Cdp "Runtime.evaluate" @{
        expression = $expression
        returnByValue = $true
        awaitPromise = $true
    }
    if ($result.exceptionDetails) { throw "Soccer365 page parser failed."
    }
    return $result.result.value
}

function Open-SoccerPage([string]$url, [string]$readyExpression) {
    [void](Invoke-Cdp "Page.navigate" @{ url = $url })
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    $state = $null
    $lastPageError = ""
    do {
        Start-Sleep -Milliseconds 500
        try {
            $state = Invoke-PageScript "({ready:document.readyState,title:document.title,ok:Boolean($readyExpression)})"
            if ($state.title -match "Cloudflare|Attention Required|blocked") {
                throw "Soccer365 blocked the automatic browser. Open the site once in Chrome and retry."
            }
            if ($state.ready -eq "complete" -and $state.ok) { return }
        } catch {
            $lastPageError = $_.Exception.Message
            if ($_.Exception.Message -match "blocked") { throw }
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    $stateText = if ($state) { "ready=$($state.ready), title=$($state.title), ok=$($state.ok)" } else { "no page state" }
    throw "Timed out while loading Soccer365: $url ($stateText; $lastPageError)"
}

function Stop-SoccerBrowser {
    if ($cdpSocket) {
        try { [void]$cdpSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cdpToken).GetAwaiter().GetResult() } catch {}
        try { $cdpSocket.Dispose() } catch {}
    }
    if ($browserProcess) {
        try { Stop-Process -Id $browserProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($browserProfile) {
        $resolved = [System.IO.Path]::GetFullPath($browserProfile)
        $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
            ([System.IO.Path]::GetFileName($resolved) -like "incheon-s365-*")) {
            Start-Sleep -Milliseconds 500
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-CompetitionGames([string]$url) {
    Open-SoccerPage $url "document.querySelectorAll('.cmp_stg_ttl').length > 0"
    $expression = @'
(() => Array.from(document.querySelectorAll('.cmp_stg_ttl')).flatMap(title => {
  const match = title.textContent.match(/(\d+)\s*-round/i);
  if (!match) return [];
  const round = Number(match[1]);
  const body = title.nextElementSibling;
  if (!body) return [];
  return Array.from(body.querySelectorAll('.game_block')).map(block => {
    const link = block.querySelector('a.game_link');
    const home = block.querySelector('.ht .name span')?.textContent.trim() || '';
    const away = block.querySelector('.at .name span')?.textContent.trim() || '';
    const homeScoreText = block.querySelector('.ht .gls')?.textContent.trim() || '';
    const awayScoreText = block.querySelector('.at .gls')?.textContent.trim() || '';
    const href = link?.getAttribute('href') || '';
    const idMatch = href.match(/\/games\/(\d+)\//);
    return {
      round,
      id: link?.getAttribute('dt-id') || (idMatch ? idMatch[1] : null),
      date: block.querySelector('.status .size10')?.textContent.trim() || '',
      home,
      away,
      homeScore: /^\d+$/.test(homeScoreText) ? Number(homeScoreText) : null,
      awayScore: /^\d+$/.test(awayScoreText) ? Number(awayScoreText) : null,
      href
    };
  });
}))()
'@
    return @(Invoke-PageScript $expression)
}

function Get-Standings {
    Open-SoccerPage $competitionUrl 'document.querySelectorAll("table").length > 0 && document.body.innerText.includes("Incheon United")'
    $expression = @'
(() => {
  const table = Array.from(document.querySelectorAll('table')).find(t => t.querySelectorAll('a[href^="/clubs/"]').length >= 12);
  if (!table) return [];
  return Array.from(table.querySelectorAll('tbody tr')).map(row => {
    const cells = Array.from(row.querySelectorAll('td')).map(c => c.textContent.trim());
    if (cells.length < 10 || !/^\d+$/.test(cells[0])) return null;
    return {
      pos:Number(cells[0]), team:cells[1], pld:Number(cells[2]), w:Number(cells[3]),
      d:Number(cells[4]), l:Number(cells[5]), gf:Number(cells[6]), ga:Number(cells[7]),
      pts:Number(cells[9])
    };
  }).filter(Boolean).slice(0,12);
})()
'@
    return @(Invoke-PageScript $expression)
}

function Get-PlayerStats {
    Open-SoccerPage $clubPlayersUrl "document.querySelectorAll('[role=grid] [role=row]').length > 5"
    $expression = @'
(() => Array.from(document.querySelectorAll('[role=grid] [role=row]')).map(row => {
  const cells = Array.from(row.querySelectorAll('[role=gridcell]'));
  const link = cells[0]?.querySelector('a[href^="/players/"]');
  if (!link || cells.length < 6) return null;
  const idMatch = link.getAttribute('href').match(/\/players\/(\d+)\//);
  const number = value => {
    const text = String(value || '').replace(/,/g,'').trim();
    return /^-?\d+$/.test(text) ? Number(text) : 0;
  };
  return {
    id:idMatch ? idMatch[1] : '', name:link.textContent.trim(), info:cells[0].textContent.trim(),
    goals:number(cells[1].textContent), assists:number(cells[2].textContent),
    appearances:number(cells[3].textContent), substitutes:number(cells[4].textContent)
  };
}).filter(Boolean))()
'@
    return @(Invoke-PageScript $expression)
}

function Get-MatchDetails([string]$gameId, [bool]$incheonIsHome) {
    $url = "https://soccer365.net/games/$gameId/"
    Open-SoccerPage $url "document.querySelectorAll('#tm-lineup table').length >= 2"
    $teamIndex = if ($incheonIsHome) { 0 } else { 1 }
    $sideClass = if ($incheonIsHome) { "event_ht" } else { "event_at" }
    $expression = @"
(() => {
  const teamIndex = $teamIndex;
  const readPlayer = row => {
    const nameNode = row.querySelector('td.player .img16 span');
    const link = row.querySelector('td.player a[href^=\"/players/\"]');
    const idMatch = link?.getAttribute('href').match(/\\/players\\/(\\d+)\\//);
    return {name:(nameNode?.textContent || '').trim(), id:idMatch ? idMatch[1] : ''};
  };
  const lineupBlocks = Array.from(document.querySelectorAll('#tm-lineup > div')).filter(x => x.querySelector('table'));
  const subBlocks = Array.from(document.querySelectorAll('#tm-subst > div')).filter(x => x.querySelector('table'));
  const start = Array.from(lineupBlocks[teamIndex]?.querySelectorAll('tr') || []).map(readPlayer).filter(x => x.name);
  const benchRows = Array.from(subBlocks[teamIndex]?.querySelectorAll('tr') || []);
  const bench = benchRows.map(readPlayer).filter(x => x.name);
  const sub = benchRows.filter(row => row.querySelector('[class*=\"subs_green\"]')).map(readPlayer).filter(x => x.name);
  const goals = Array.from(document.querySelectorAll('.$sideClass')).filter(x => x.querySelector('.live_goal')).map(x => {
    const link = x.querySelector('.img16 a[href^=\"/players/\"]');
    const idMatch = link?.getAttribute('href').match(/\\/players\\/(\\d+)\\//);
    return {
      scorer:{name:(x.querySelector('.img16 span')?.textContent || '').trim(),id:idMatch ? idMatch[1] : ''},
      assist:(x.querySelector('.assist')?.textContent || '').trim()
    };
  });
  const readInfo = label => {
    const node = Array.from(document.querySelectorAll('.preview_param')).find(x => x.textContent.trim() === label);
    return node ? node.parentElement.textContent.replace(label,'').trim() : '';
  };
  return {start,sub,bench,goals,viewers:readInfo('Viewers'),referee:readInfo('Referees')};
})()
"@
    return Invoke-PageScript $expression
}

function Convert-DateInfo([string]$shortDate) {
    if ($shortDate -notmatch "(?<day>\d{1,2})\.(?<month>\d{1,2})") { return $null }
    $date = New-Object DateTime([int]$config.season, [int]$Matches.month, [int]$Matches.day)
    return [pscustomobject]@{
        display = "$($date.Month)$($config.labels.month) $($date.Day)$($config.labels.day)"
        dow = [string]$config.weekdays[[int]$date.DayOfWeek]
        iso = $date.ToString("yyyy-MM-dd")
    }
}

function Convert-GameRecord($raw) {
    $date = Convert-DateInfo ([string]$raw.date)
    return [pscustomobject]@{
        round = [int]$raw.round
        gameId = if ($raw.id) { [string]$raw.id } else { $null }
        date = $date
        home = Convert-TeamName ([string]$raw.home)
        away = Convert-TeamName ([string]$raw.away)
        homeScore = if ($null -ne $raw.homeScore) { [int]$raw.homeScore } else { $null }
        awayScore = if ($null -ne $raw.awayScore) { [int]$raw.awayScore } else { $null }
        href = [string]$raw.href
    }
}

function Get-ResultLabel([int]$gf, [int]$ga) {
    if ($gf -gt $ga) { return [string]$config.labels.win }
    if ($gf -eq $ga) { return [string]$config.labels.draw }
    return [string]$config.labels.loss
}

function New-SplitStat([string]$key, $played) {
    $games = @($played)
    $w = 0; $d = 0; $l = 0; $gf = 0; $ga = 0
    foreach ($game in $games) {
        if ($game.res -eq $config.labels.win) { $w++ }
        elseif ($game.res -eq $config.labels.draw) { $d++ }
        elseif ($game.res -eq $config.labels.loss) { $l++ }
        $gf += [int]$game.gf; $ga += [int]$game.ga
    }
    $pts = $w * 3 + $d
    return [ordered]@{ k=$key; pld=$games.Count; w=$w; d=$d; l=$l; pts=$pts; gf=[int]$gf; ga=[int]$ga; gd=[int]$gf-[int]$ga; ppg=$(if($games.Count){[Math]::Round($pts/$games.Count,2)}else{0}) }
}

function New-AttendanceStat($matches, $oldStat) {
    $values = @($matches | Where-Object { $null -ne $_.att } | ForEach-Object { [int]$_.att })
    $total = ($values | Measure-Object -Sum).Sum
    if ($null -eq $total) { $total = 0 }
    $avg = if ($values.Count) { [Math]::Round($total / $values.Count, 0) } else { 0 }
    $pyAvg = if ($oldStat -and $null -ne $oldStat.py_avg) { [double]$oldStat.py_avg } else { 0 }
    $yoy = if ($pyAvg) { ($avg / $pyAvg) - 1 } else { 0 }
    return [ordered]@{ n=$values.Count; tot=[int]$total; avg=[int]$avg; py_avg=$pyAvg; yoy=$yoy }
}

function Build-HistoryAndTeamMatches($roundGames, $teamNames) {
    $stats = @{}
    $history = [ordered]@{}
    $teamMatches = [ordered]@{}
    foreach ($team in $teamNames) {
        $stats[$team] = [ordered]@{ pld=0; w=0; d=0; l=0; gf=0; ga=0; pts=0 }
        $history[$team] = @()
        $teamMatches[$team] = @()
    }

    foreach ($round in @($roundGames.Keys | Sort-Object { [int]$_ })) {
        foreach ($game in @($roundGames[$round])) {
            foreach ($side in @(
                [pscustomobject]@{ team=$game.home; opp=$game.away; gf=$game.homeScore; ga=$game.awayScore; ha=$config.labels.home },
                [pscustomobject]@{ team=$game.away; opp=$game.home; gf=$game.awayScore; ga=$game.homeScore; ha=$config.labels.away }
            )) {
                $s = $stats[$side.team]
                $s.pld++; $s.gf += [int]$side.gf; $s.ga += [int]$side.ga
                $result = Get-ResultLabel ([int]$side.gf) ([int]$side.ga)
                if ($result -eq $config.labels.win) { $s.w++; $s.pts += 3 }
                elseif ($result -eq $config.labels.draw) { $s.d++; $s.pts += 1 }
                else { $s.l++ }
                $teamMatches[$side.team] += ,([ordered]@{ round=[int]$round; opp=$side.opp; ha=$side.ha; gf=[int]$side.gf; ga=[int]$side.ga; res=$result })
            }
        }
        $order = @($teamNames | Sort-Object `
            @{Expression={-$stats[$_].pts}}, `
            @{Expression={-$stats[$_].gf}}, `
            @{Expression={-($stats[$_].gf-$stats[$_].ga)}}, `
            @{Expression={-$stats[$_].w}}, `
            @{Expression={$_}})
        for ($i=0; $i -lt $order.Count; $i++) { $history[$order[$i]] += ,($i+1) }
    }
    return [pscustomobject]@{ history=$history; teamMatches=$teamMatches }
}

function Get-ExcelColor([string]$hex) {
    $hex = $hex.TrimStart('#')
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    return $r + ($g * 256) + ($b * 65536)
}

function Set-ExcelCell($sheet, [int]$row, [int]$col, $value) {
    $cell = $sheet.Cells.Item($row, $col)
    try {
        if ($null -eq $value -or ($value -is [string] -and $value -eq "")) { $cell.ClearContents() }
        elseif ($value -is [byte] -or $value -is [int16] -or $value -is [int32] -or $value -is [int64] -or
                $value -is [single] -or $value -is [double] -or $value -is [decimal]) {
            $cell.Value2 = [double]$value
        }
        else { $cell.Value2 = [string]$value }
    } catch {
        $kind = if ($null -eq $value) { "null" } else { $value.GetType().FullName }
        throw "Excel write failed at row=$row col=$col type=$kind value=[$value]: $($_.Exception.Message)"
    }
}

function Update-Workbook($matches, $lineups, $standings, [string]$asof) {
    if (-not (Test-Path -LiteralPath $workbookPath)) { throw "Workbook not found: $workbookPath" }
    $excel = $null; $book = $null; $main = $null; $lineupSheet = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $book = $excel.Workbooks.Open($workbookPath, 0, $false)
        $main = $book.Worksheets.Item([string]$config.paths.main_sheet)
        $lineupSheet = $book.Worksheets.Item([string]$config.paths.lineup_sheet)

        foreach ($match in @($matches | Where-Object { $_.comp -eq $config.labels.competition })) {
            $round = [int]$match.round; if ($round -lt 1 -or $round -gt 38) { continue }
            $row = $round + 2
            Set-ExcelCell $main $row 1 $config.labels.competition
            # 경기 당일에는 Soccer365가 날짜 대신 라이브 표기를 보내 파싱이 실패한다.
            # 이때 null 로 덮어쓰면 기존 일정이 지워지므로, 값이 있을 때만 기록한다.
            if ($match.date) { Set-ExcelCell $main $row 2 $match.date }
            if ($match.dow)  { Set-ExcelCell $main $row 3 $match.dow }
            Set-ExcelCell $main $row 4 $round
            Set-ExcelCell $main $row 5 $match.opp
            Set-ExcelCell $main $row 6 $match.ha
            Set-ExcelCell $main $row 7 $match.gf
            Set-ExcelCell $main $row 8 $match.ga
            Set-ExcelCell $main $row 9 $match.res
            $main.Range($main.Cells.Item($row,13), $main.Cells.Item($row,22)).ClearContents()
            for ($i=0; $i -lt [Math]::Min(4,@($match.scorers).Count); $i++) { Set-ExcelCell $main $row (13+$i) @($match.scorers)[$i] }
            for ($i=0; $i -lt [Math]::Min(4,@($match.assists).Count); $i++) { Set-ExcelCell $main $row (17+$i) @($match.assists)[$i] }
            Set-ExcelCell $main $row 21 $match.att
            Set-ExcelCell $main $row 22 $match.ref
        }

        foreach ($lineup in @($lineups)) {
            $round = [int]$lineup.round; if ($round -lt 1 -or $round -gt 38) { continue }
            $row = $round + 1
            Set-ExcelCell $lineupSheet $row 1 $round
            Set-ExcelCell $lineupSheet $row 2 $lineup.opp
            $lineupSheet.Range($lineupSheet.Cells.Item($row,3), $lineupSheet.Cells.Item($row,19)).ClearContents()
            for ($i=0; $i -lt [Math]::Min(11,@($lineup.start).Count); $i++) { Set-ExcelCell $lineupSheet $row (3+$i) @($lineup.start)[$i] }
            for ($i=0; $i -lt [Math]::Min(6,@($lineup.sub).Count); $i++) { Set-ExcelCell $lineupSheet $row (14+$i) @($lineup.sub)[$i] }
        }

        Set-ExcelCell $main 1 61 ([string]$config.standings_title + "   (" + $asof + ")")
        $main.Range("BI3:BR14").Interior.Pattern = -4142
        $main.Range("BI3:BR14").Font.Bold = $false
        $main.Range("BI3:BR14").Font.Color = Get-ExcelColor "1A1A1A"
        for ($i=0; $i -lt [Math]::Min(12,@($standings).Count); $i++) {
            $row = 3 + $i; $st = @($standings)[$i]
            $values = @($st.pos,$st.team,$st.pld,$st.w,$st.d,$st.l,$st.gf,$st.ga,$null,$st.pts)
            for ($j=0; $j -lt 10; $j++) {
                if ($j -eq 8) { $main.Cells.Item($row,69).Formula = "=BO$row-BP$row" }
                else { Set-ExcelCell $main $row (61+$j) $values[$j] }
            }
            $zone = switch ([int]$st.pos) { 1 {"D6E9FF"} 2 {"E9F3FF"} 3 {"E9F3FF"} 12 {"FFE3E0"} default {$null} }
            if ($zone) { $main.Range($main.Cells.Item($row,61),$main.Cells.Item($row,70)).Interior.Color = Get-ExcelColor $zone }
            if ($st.team -eq $teamMap["Incheon United"]) {
                $range = $main.Range($main.Cells.Item($row,61),$main.Cells.Item($row,70))
                $range.Interior.Color = Get-ExcelColor "E2B33C"
                $range.Font.Bold = $true
            }
        }

        $excel.CalculateFullRebuild()
        $book.Save()
    } finally {
        if ($book) { try { $book.Close($true) } catch {} }
        if ($excel) { try { $excel.Quit() } catch {} }
        foreach ($obj in @($lineupSheet,$main,$book,$excel)) { if ($obj) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {} } }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
}

if ($ApplyExistingData) {
    $existing = Read-Utf8Json $dataPath
    if ($null -eq $existing) { throw "Existing data.json was not found." }
    Update-Workbook -matches @($existing.matches) -lineups @($existing.lineups) -standings @($existing.table) -asof ([string]$existing.asof)
    Write-Host "Existing data.json was applied to Excel."
    exit 0
}

Write-Host "[1/5] Reading Soccer365 standings, results, schedule, and player stats..."
$current = Read-Utf8Json $dataPath
if ($null -eq $current) { throw "Existing data.json is required for the first migration run." }

try {
    Start-SoccerBrowser
    $rawResults = Get-CompetitionGames $resultsUrl
    $rawSchedule = Get-CompetitionGames $scheduleUrl
    $rawStandings = Get-Standings
    $rawPlayerStats = Get-PlayerStats

    $results = @($rawResults | ForEach-Object { Convert-GameRecord $_ } | Where-Object { $null -ne $_.homeScore -and $null -ne $_.awayScore })
    $schedule = @($rawSchedule | ForEach-Object { Convert-GameRecord $_ })
    $standings = @($rawStandings | ForEach-Object {
        [ordered]@{ pos=[int]$_.pos; team=Convert-TeamName([string]$_.team); pld=[int]$_.pld; w=[int]$_.w; d=[int]$_.d; l=[int]$_.l; gf=[int]$_.gf; ga=[int]$_.ga; gd=[int]$_.gf-[int]$_.ga; pts=[int]$_.pts }
    })

    $currentMatchesByRound = @{}
    foreach ($m in @($current.matches)) {
        $roundNum = 0
        if ($m.comp -eq $config.labels.competition -and [int]::TryParse([string]$m.round, [ref]$roundNum)) { $currentMatchesByRound["$roundNum"] = $m }
    }
    $currentLineupsByRound = @{}
    foreach ($l in @($current.lineups)) {
        $roundNum = 0
        if ([int]::TryParse([string]$l.round, [ref]$roundNum)) { $currentLineupsByRound["$roundNum"] = $l }
    }

    $incheonKo = [string]$teamMap["Incheon United"]
    $incheonResultsByRound = @{}
    foreach ($g in $results) { if ($g.home -eq $incheonKo -or $g.away -eq $incheonKo) { $incheonResultsByRound["$($g.round)"] = $g } }
    $incheonScheduleByRound = @{}
    foreach ($g in $schedule) { if ($g.home -eq $incheonKo -or $g.away -eq $incheonKo) { $incheonScheduleByRound["$($g.round)"] = $g } }

    Write-Host "[2/5] Merging Incheon matches and lineups..."
    $matches = @(); $lineups = @()
    for ($round=1; $round -le 38; $round++) {
        $key = "$round"; $old = $currentMatchesByRound[$key]; $oldLineup = $currentLineupsByRound[$key]
        $resultGame = $incheonResultsByRound[$key]; $scheduleGame = $incheonScheduleByRound[$key]
        $sourceGame = if ($resultGame) { $resultGame } else { $scheduleGame }
        $isHome = if ($sourceGame) { $sourceGame.home -eq $incheonKo } else { $false }
        $opp = if ($sourceGame) { if ($isHome) { $sourceGame.away } else { $sourceGame.home } } elseif ($old) { $old.opp } else { $null }
        # 경기 당일에는 Soccer365가 날짜 대신 라이브 표기를 보내 파싱이 실패한다.
        # 이때는 직전 data.json 에 저장돼 있던 일정을 그대로 유지한다.
        $date = if ($sourceGame -and $sourceGame.date) { $sourceGame.date }
                elseif ($old -and $old.iso) {
                    [pscustomobject]@{ display=[string]$old.date; dow=[string]$old.dow; iso=[string]$old.iso }
                }
                else { $null }
        [object[]]$scorers = @(); [object[]]$assists = @()
        if ($old -and ($old.scorers -is [System.Array] -or $old.scorers -is [string])) { $scorers = [object[]]@($old.scorers) }
        if ($old -and ($old.assists -is [System.Array] -or $old.assists -is [string])) { $assists = [object[]]@($old.assists) }
        $att = if ($old) { $old.att } else { $null }
        $ref = if ($old) { $old.ref } else { $null }
        [object[]]$start = @(); [object[]]$sub = @(); [object[]]$bench = @()
        if ($oldLineup -and $oldLineup.start -is [System.Array]) { $start = [object[]]@($oldLineup.start) }
        if ($oldLineup -and $oldLineup.sub -is [System.Array]) { $sub = [object[]]@($oldLineup.sub) }
        if ($oldLineup -and $oldLineup.bench -is [System.Array]) { $bench = [object[]]@($oldLineup.bench) }

        if ($resultGame) {
            $gf = if ($isHome) { [int]$resultGame.homeScore } else { [int]$resultGame.awayScore }
            $ga = if ($isHome) { [int]$resultGame.awayScore } else { [int]$resultGame.homeScore }
            $scoreChanged = (-not $old) -or $null -eq $old.gf -or [int]$old.gf -ne $gf -or [int]$old.ga -ne $ga
            if ($scoreChanged -or $start.Count -ne 11) {
                if (-not $resultGame.gameId) { throw "Missing Soccer365 game id for round $round." }
                $detail = Get-MatchDetails $resultGame.gameId $isHome
                $start = @($detail.start | ForEach-Object { Convert-PlayerName ([string]$_.name) ([string]$_.id) })
                $sub = @($detail.sub | ForEach-Object { Convert-PlayerName ([string]$_.name) ([string]$_.id) })
                $bench = @($detail.bench | ForEach-Object { Convert-PlayerName ([string]$_.name) ([string]$_.id) })
                $scorers = @($detail.goals | ForEach-Object { Convert-PlayerName ([string]$_.scorer.name) ([string]$_.scorer.id) })
                $assists = @($detail.goals | Where-Object { $_.assist } | ForEach-Object { Convert-PlayerName ([string]$_.assist) })
                if ($isHome -and $detail.viewers) { $att = [int](([string]$detail.viewers) -replace '[^0-9]','') } else { $att = $null }
                $ref = Convert-RefereeName ([string]$detail.referee)
            }
            $match = [ordered]@{ comp=$config.labels.competition; date=$date.display; dow=$date.dow; round=$round; opp=$opp; ha=$(if($isHome){$config.labels.home}else{$config.labels.away}); gf=$gf; ga=$ga; res=$(Get-ResultLabel $gf $ga); scorers=[object[]]$scorers; assists=[object[]]$assists; att=$att; ref=$ref; iso=$date.iso; gameId=$resultGame.gameId }
        } else {
            $match = [ordered]@{ comp=$config.labels.competition; date=$(if($date){$date.display}else{$null}); dow=$(if($date){$date.dow}else{$null}); round=$round; opp=$opp; ha=$(if($sourceGame){if($isHome){$config.labels.home}else{$config.labels.away}}else{$null}); gf=$null; ga=$null; res=$null; scorers=@(); assists=@(); att=$null; ref=$null; iso=$(if($date){$date.iso}else{$null}); gameId=$null }
            $start=[object[]]@(); $sub=[object[]]@(); $bench=[object[]]@()
        }
        $matches += ,$match
        $lineups += ,([ordered]@{ round=$round; opp=$opp; start=[object[]]$start; sub=[object[]]$sub; bench=[object[]]$bench })
    }
    foreach ($m in @($current.matches | Where-Object { $_.comp -ne $config.labels.competition })) { $matches += ,$m }

    $statsByName = @{}
    foreach ($raw in $rawPlayerStats) {
        $name = Convert-PlayerName ([string]$raw.name) ([string]$raw.id)
        if (-not $name -or [int]$raw.appearances -le 0) { continue }
        $isGoalkeeper = ([string]$raw.info) -match "goalie"
        $goals = if ($isGoalkeeper) { 0 } else { [Math]::Max(0,[int]$raw.goals) }
        $against = if ($isGoalkeeper) { [Math]::Abs([Math]::Min(0,[int]$raw.goals)) } else { 0 }
        $statsByName[$name] = [ordered]@{ name=$name; app=[int]$raw.appearances; start=[int]$raw.appearances-[int]$raw.substitutes; sub=[int]$raw.substitutes; g=$goals; a=[int]$raw.assists; ga=$against }
    }
    $players = @(); $seenPlayers = @{}
    foreach ($oldPlayer in @($current.players)) {
        $name = [string]$oldPlayer.name; $seenPlayers[$name] = $true
        if ($statsByName.ContainsKey($name)) { $players += ,$statsByName[$name] }
        else { $players += ,$oldPlayer }
    }
    foreach ($name in $statsByName.Keys) { if (-not $seenPlayers.ContainsKey($name)) { $players += ,$statsByName[$name] } }

    $played = @($matches | Where-Object { $_.comp -eq $config.labels.competition -and $_.res })
    $split = @(
        New-SplitStat -key $config.labels.all -played $played
        New-SplitStat -key $config.labels.home -played @($played | Where-Object { $_.ha -eq $config.labels.home })
        New-SplitStat -key $config.labels.away -played @($played | Where-Object { $_.ha -eq $config.labels.away })
    )

    $refs = @(); $refMap = [ordered]@{}
    foreach ($m in $played) {
        if (-not $m.ref) { continue }
        if (-not $refMap.Contains($m.ref)) { $refMap[$m.ref] = [ordered]@{name=$m.ref;pld=0;w=0;d=0;l=0;pts=0} }
        $r = $refMap[$m.ref]; $r.pld++
        if($m.res -eq $config.labels.win){$r.w++;$r.pts+=3}elseif($m.res -eq $config.labels.draw){$r.d++;$r.pts++}else{$r.l++}
    }
    foreach ($v in $refMap.Values) { $refs += ,$v }

    $klHome = @($played | Where-Object { $_.ha -eq $config.labels.home })
    $faPlayed = @($matches | Where-Object { $_.comp -ne $config.labels.competition -and $_.res -and $_.ha -eq $config.labels.home })
    $att = [ordered]@{ kl=$(New-AttendanceStat -matches $klHome -oldStat $current.att.kl); fa=$(New-AttendanceStat -matches $faPlayed -oldStat $current.att.fa) }

    $roundGames = @{}; $leagueResults = [ordered]@{}
    foreach ($g in $results) {
        $key = "$($g.round)"; if (-not $roundGames.ContainsKey($key)) { $roundGames[$key] = @() }
        $roundGames[$key] += ,$g
    }
    foreach ($key in @($roundGames.Keys | Sort-Object { [int]$_ })) {
        $gameRows = New-Object System.Collections.Generic.List[object]
        foreach ($game in @($roundGames[$key])) {
            [void]$gameRows.Add([object[]]@($game.home,[int]$game.homeScore,$game.away,[int]$game.awayScore))
        }
        $leagueResults[$key] = $gameRows.ToArray()
    }
    $teamNames = @($config.teams.PSObject.Properties | ForEach-Object { [string]$_.Value })
    $historyData = Build-HistoryAndTeamMatches -roundGames $roundGames -teamNames $teamNames

    $latestRound = ($results | Measure-Object -Property round -Maximum).Maximum
    $latestGames = @($results | Where-Object { $_.round -eq $latestRound })
    $latestDate = @($latestGames | Where-Object { $_.date } | ForEach-Object { $_.date.iso } | Sort-Object | Select-Object -Last 1)[0]
    $roundState = if ($latestGames.Count -ge 6) { $config.labels.round_end } else { $config.labels.round_progress }
    $asof = "$latestDate - ${latestRound}R $roundState"

    $keyPlayerRaw = Read-Utf8Json (Join-Path $toolDir "key_players.json")
    $keyPlayers = [ordered]@{}
    foreach ($p in $keyPlayerRaw.PSObject.Properties) { if (-not $p.Name.StartsWith("_")) { $keyPlayers[$p.Name] = $p.Value } }

    $today = (Get-Date).ToString("yyyy-MM-dd")
    $data = [ordered]@{
        matches=$matches; players=$players; split=$split; table=$standings; refs=$refs; att=$att
        runner=@($current.runner); lineups=$lineups; positions=$historyData.history
        teamMatches=$historyData.teamMatches; keyPlayers=$keyPlayers; today=$today; updated=$today; asof=$asof
        sources=[ordered]@{ competition=$competitionUrl; results=$resultsUrl; schedule=$scheduleUrl; playerStats=$clubPlayersUrl }
    }

    if (-not $SkipExcel) {
        Write-Host "[3/5] Updating Excel while preserving the workbook layout..."
        Update-Workbook -matches $matches -lineups $lineups -standings $standings -asof $asof
    } else { Write-Host "[3/5] Excel update skipped." }

    Write-Host "[4/5] Rebuilding data.json and the HTML dashboard..."
    $dataJson = $data | ConvertTo-Json -Depth 100
    $dataJsonCompact = $data | ConvertTo-Json -Depth 100 -Compress
    Write-Utf8 $dataPath $dataJson
    Write-Utf8 $leagueResultsPath ($leagueResults | ConvertTo-Json -Depth 30)
    $snapshot = [ordered]@{ collectedAt=(Get-Date).ToString("s"); results=$results; schedule=$schedule; standings=$standings; playerStats=$rawPlayerStats; urls=$data.sources }
    Write-Utf8 $snapshotPath ($snapshot | ConvertTo-Json -Depth 100)
    $template = [System.IO.File]::ReadAllText($templatePath, $utf8NoBom)
    if (-not $template.Contains("__DATA__")) { throw "Dashboard template placeholder __DATA__ was not found." }
    $page = $template.Replace("__DATA__", $dataJsonCompact)
    Write-Utf8 $dashboardPath $page
    Write-Utf8 $indexPath $page

    Write-Host "[5/5] Soccer365 update completed."
    Write-Host ("  Standings: " + @($standings | Where-Object { $_.team -eq $incheonKo })[0].pos + " / " + $standings.Count)
    Write-Host ("  Played: " + $played.Count + " league matches")
    if ($unknownNames.Count) {
        Write-Warning ("Unmapped Soccer365 player names were kept in English: " + (($unknownNames | Sort-Object) -join ", "))
        Write-Warning "Add them to soccer365_config.json if a Korean display name is needed."
    }
} finally {
    Stop-SoccerBrowser
}
