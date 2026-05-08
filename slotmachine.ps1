<#
Animated Slot Machine (PowerShell)
- 3 rows x 5 columns
- Emoji visuals

Usage: Run this script in Windows Terminal / PowerShell. Press Enter to spin, Q to quit.
#>

$Symbols = @(
    '🍒', '🍋', '🍇', '🍉', '🔔', '🍀', ' 7'
)

$Rows = 3
$Cols = 5
# high score tracker (script scope so functions share it)
$script:HighScore = 0

function Render-Grid {
    param(
        [string[][]]$Grid
    )
    Clear-Host
    # show high score at top
    Write-Host "=== Highest score: $script:HighScore ====" -ForegroundColor yellow
    write-host ""
    Write-Host "╔" -NoNewline
    for ($c = 0; $c -lt $Cols; $c++) { Write-Host "═══" -NoNewline; if ($c -lt $Cols - 1) { Write-Host "╦" -NoNewline } }
    Write-Host "╗"

    for ($r = 0; $r -lt $Rows; $r++) {
        # add left padding (replaces removed left border) so columns line up
        Write-Host " " -NoNewline
        for ($c = 0; $c -lt $Cols; $c++) {
            $sym = $Grid[$c][$r]
            if ($sym -eq ' 7') {
                Write-Host ' 7' -NoNewline -ForegroundColor Green
            }
            else {
                Write-Host "$sym" -NoNewline
            }
            if ($c -lt $Cols - 1) { Write-Host "  " -NoNewline }
        }
        Write-Host ""
    }

    Write-Host "╚" -NoNewline
    for ($c = 0; $c -lt $Cols; $c++) { Write-Host "═══" -NoNewline; if ($c -lt $Cols - 1) { Write-Host "╩" -NoNewline } }
    Write-Host "╝"
}

function Spin-Once {
    # Initialize display grid as a jagged array: columns of rows
    $display = @()
    for ($c = 0; $c -lt $Cols; $c++) {
        $col = @()
        for ($r = 0; $r -lt $Rows; $r++) { $col += $Symbols | Get-Random }
        $display += , $col
    }

    # Random durations per column to stagger stops (increased for slower spins)
    $durations = 0..($Cols - 1) | ForEach-Object { Get-Random -Minimum 18 -Maximum 36 }
    $locked = 0..($Cols - 1) | ForEach-Object { $false }
    $finals = @()

    while ($locked -contains $false) {
        for ($c = 0; $c -lt $Cols; $c++) {
            if (-not $locked[$c]) {
                for ($r = 0; $r -lt $Rows; $r++) {
                    $display[$c][$r] = $Symbols | Get-Random
                }
            }
        }

        Render-Grid -Grid $display

        # decrease durations with a small random factor to simulate deceleration
        for ($c = 0; $c -lt $Cols; $c++) {
            if (-not $locked[$c]) {
                $step = (Get-Random -Minimum 1 -Maximum 3)
                $durations[$c] -= $step
                if ($durations[$c] -le 0) {
                    # lock this column and pick its final symbols
                    $locked[$c] = $true
                    $colFinal = @()
                    for ($r = 0; $r -lt $Rows; $r++) { $colFinal += $Symbols | Get-Random }
                    $finals += , $colFinal
                    # set display to final immediately for a nice stop effect
                    for ($r = 0; $r -lt $Rows; $r++) { $display[$c][$r] = $colFinal[$r] }
                }
            }
        }

        # sleep shorter when many columns still spinning, longer when nearing stop
        $remaining = ($locked | Where-Object { -not $_ }).Count
        $ms = if ($remaining -ge ($Cols / 2)) { 120 } else { 260 }
        Start-Sleep -Milliseconds $ms
    }

    # final render to ensure everything settled
    Render-Grid -Grid $display

    return $display
}

function Score-Grid {
    param(
        [string[][]]$Grid
    )

    # base points per symbol
    $pointsMap = @{
        '🍒' = 30; '🍋' = 30;          # cherries, citrus
        '🍇' = 50; '🍉' = 50;           # raisins (grapes), watermelon
        '🔔' = 70; '🍀' = 70;           # bell, clover
        ' 7' = 100;                   # seven
    }

    $dirs = @(
        @{dx = 1; dy = 0; name = 'Horizontal' },
        @{dx = 0; dy = 1; name = 'Vertical' },
        @{dx = 1; dy = 1; name = 'DiagDown' },
        @{dx = 1; dy = -1; name = 'DiagUp' }
    )

    $rows = $Rows
    $cols = $Cols
    $matches = @()
    $total = 0

    for ($c = 0; $c -lt $cols; $c++) {
        for ($r = 0; $r -lt $rows; $r++) {
            $sym = $Grid[$c][$r]
            if (-not $sym) { continue }

            foreach ($d in $dirs) {
                $dx = $d.dx; $dy = $d.dy
                # skip if previous cell in this direction has same symbol (we only start at sequence head)
                $px = $c - $dx; $py = $r - $dy
                if ($px -ge 0 -and $px -lt $cols -and $py -ge 0 -and $py -lt $rows) {
                    if ($Grid[$px][$py] -eq $sym) { continue }
                }

                # walk forward
                $len = 1
                $x = $c + $dx; $y = $r + $dy
                while ($x -ge 0 -and $x -lt $cols -and $y -ge 0 -and $y -lt $rows -and $Grid[$x][$y] -eq $sym) {
                    $len++
                    $x += $dx; $y += $dy
                }

                if ($len -ge 3) {
                    $base = if ($pointsMap.ContainsKey($sym)) { $pointsMap[$sym] } else { 1 }
                    $pts = [int]($base * $len)
                    $total += $pts
                    $matches += , [pscustomobject]@{ Symbol = $sym; Length = $len; Direction = $d.name; Points = $pts }
                }
            }
        }
    }

    return @{ Total = $total; Matches = $matches }
}

function Start-SlotMachine {
    Write-Host "Controls: Enter = spin, Q = quit`n"

    while ($true) {
        $input = Read-Host -Prompt "Spin? (Enter to spin / Q to quit)"
        if ($input -and $input.Trim().ToUpper() -eq 'Q') { break }

        $result = Spin-Once

        # Score evaluation (horizontal, vertical, diagonal sequences length 3-5)
        $score = Score-Grid -Grid $result
        if ($score.Matches.Count -gt 0) {
            # length-based multipliers (3→×1, 4→×2, 5→×5)
            $lenMult = { param($len) switch ($len) { 3 { 1 } 4 { 2 } 5 { 5 } default { 1 } } }
            $points = 0
            foreach ($m in $score.Matches) {
                $mBase = [int]$m.Points
                $lm = [int](& $lenMult $m.Length)
                $matchPoints = $mBase * $lm
                $points += $matchPoints
                Write-Host " - $($m.Length)-in-a-row $($m.Symbol) ($($m.Direction)) -> $matchPoints pts" -foregroundcolor darkgray
            }
            # combo bonus for multiple matches (25% extra per additional match)
            $comboMultiplier = if ($score.Matches.Count -gt 1) { 1 + 1 * ($score.Matches.Count - 1) } else { 1 }
            $totalPoints = [math]::Floor($points * $comboMultiplier)

            # jackpot: if entire grid uses the same symbol (full-board match), apply a ×20 jackpot bonus
            $allSame = $true
            $firstSym = $result[0][0]
            for ($cc = 0; $cc -lt $Cols; $cc++) {
                for ($rr = 0; $rr -lt $Rows; $rr++) {
                    if ($result[$cc][$rr] -ne $firstSym) { $allSame = $false; break }
                }
                if (-not $allSame) { break }
            }
            if ($allSame) {
                $totalPoints = $totalPoints * 20
                Write-Host "JACKPOT! All symbols match — bonus ×20 applied!" -ForegroundColor Magenta
            }

            # update high score (script-scoped)
            if ($totalPoints -gt $script:HighScore) {
                $script:HighScore = $totalPoints
            }

            Write-Host "You scored $totalPoints points (combo ×$comboMultiplier)!" -ForegroundColor Yellow
        }
        else {
            Write-Host "No big win this time. Try again!" -ForegroundColor Gray
        }

        Write-Host "`n"; Start-Sleep -Milliseconds 600
    }

    Write-Host "Thanks for playing!"
}

if ($MyInvocation.InvocationName -eq '.') {
    # dot-sourced — don't auto-run
}
else {
    Start-SlotMachine
}

