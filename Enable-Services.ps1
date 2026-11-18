<#
.SYNOPSIS
    Verifica e ativa servicos do Windows usados em verificacoes (screenshare).

.DESCRIPTION
    Mostra o estado de PcaSvc, SysMain, DPS, BAM, DusmSvc, DiagTrack e EventLog.
    Se algum estiver desativado ou parado, pergunta se voce quer ativar.
    O script funciona so na sua maquina: nao usa internet e nao envia nenhum dado.

#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Enable
)

& {
param([switch]$Check, [switch]$Enable)

$ErrorActionPreference = 'SilentlyContinue'

$Services = @(
    @{ Name = 'PcaSvc';    Default = 'demand' }
    @{ Name = 'SysMain';   Default = 'auto' }
    @{ Name = 'DPS';       Default = 'auto' }
    @{ Name = 'Bam';       Default = 'system' }
    @{ Name = 'DusmSvc';   Default = 'auto' }
    @{ Name = 'DiagTrack'; Default = 'auto' }
    @{ Name = 'EventLog';  Default = 'auto' }
)

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ServiceInfo {
    param([string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    $cim = Get-CimInstance Win32_Service -Filter "Name='$Name'"
    $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$Name'"

    $status = 'Not found'
    $start  = $null

    if ($svc) { $status = $svc.Status.ToString() }
    elseif ($drv) { $status = [string]$drv.State }

    if ($cim) { $start = $cim.StartMode }
    elseif ($drv) { $start = $drv.StartMode }
    else {
        $reg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction SilentlyContinue
        if ($reg -and $null -ne $reg.Start) {
            $map = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Auto'; 3 = 'Manual'; 4 = 'Disabled' }
            $start = $map[[int]$reg.Start]
        }
    }

    return [pscustomobject]@{
        Name      = $Name
        Status    = $status
        StartType = $start
        IsDriver  = [bool]($drv -and -not $cim)
    }
}

function Test-ServiceOk {
    param($Info, [string]$Default)

    if ($Info.Status -eq 'Not found') { return $false }
    $disabled = ($Info.StartType -eq 'Disabled')
    if ($Default -eq 'demand') { return (-not $disabled) }
    return ($Info.Status -eq 'Running' -and -not $disabled)
}

function ConvertTo-StatusText {
    param($Info)

    if ($Info.Status -eq 'Not found') { return 'Not found' }
    if ($Info.StartType -eq 'Disabled') { return 'Disabled' }
    return $Info.Status
}

function Read-Choice {
    # le Y/N sem precisar de Enter; se o console nao permitir, cai pro Read-Host
    try {
        $c = ''
        while ($c -notmatch '^[yYnN]$') { $c = [string][Console]::ReadKey($true).KeyChar }
        return $c
    }
    catch {
        return [string](Read-Host '  Ativar os servicos desativados? (Y/N)')
    }
}

function Get-StateList {
    $list = @()
    foreach ($s in $Services) {
        $i = Get-ServiceInfo $s.Name
        $list += [pscustomobject]@{
            Name      = $s.Name
            Default   = $s.Default
            Info      = $i
            StatusTxt = ConvertTo-StatusText $i
            Ok        = (Test-ServiceOk $i $s.Default)
        }
    }
    return $list
}

function Show-StateTable {
    param($States)

    Write-Host ''
    Write-Host ('  {0,-11} {1}' -f 'Service', 'Status')
    Write-Host ('  ' + ('-' * 30))
    foreach ($s in $States) {
        $color = 'Green'
        if (-not $s.Ok) { $color = 'Red' }
        Write-Host ('  {0,-11} {1}' -f $s.Name, $s.StatusTxt) -ForegroundColor $color
    }
}

$isAdmin = Test-IsAdmin
$states = Get-StateList
Show-StateTable $states

$bad = @($states | Where-Object { -not $_.Ok })
if ($bad.Count -eq 0) {
    Write-Host ''
    Write-Host '  [+] Todos os servicos estao ativos.' -ForegroundColor Green
    return
}

Write-Host ''

if ($Check) { return }

if (-not $isAdmin) {
    Write-Host '  [!] Execute como Administrador para poder ativar os servicos.' -ForegroundColor Yellow
    return
}

if (-not $Enable) {
    Write-Host ''
    Write-Host '  [Y] Ativar os servicos desativados     [N] Sair'
    $answer = Read-Choice
    if ($answer -notmatch '^[yY]') { Write-Host ''; return }
}

Write-Host ''
foreach ($b in $bad) {
    $name = $b.Name
    $i = $b.Info
    if ($i.Status -eq 'Not found') {
        Write-Host ('  [NAO ENCONTRADO] {0}: nao existe neste Windows' -f $name) -ForegroundColor Red
        continue
    }

    if ($i.StartType -eq 'Disabled') { sc.exe config $name start= $b.Default | Out-Null }
    if ($i.Status -ne 'Running') {
        if ($i.IsDriver) { sc.exe start $name | Out-Null }
        else { Start-Service -Name $name -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 600

    $now = Get-ServiceInfo $name
    if ($now.Status -eq 'Running' -and $now.StartType -ne 'Disabled') {
        Write-Host ('  [ATIVADO] {0}: {1} (inicio: {2})' -f $name, $now.Status, $now.StartType) -ForegroundColor Green
    }
    elseif ($now.StartType -ne 'Disabled') {
        Write-Host ('  [PARCIAL] {0}: inicio definido como {1}, ainda nao esta em execucao (pode precisar reiniciar)' -f $name, $now.StartType) -ForegroundColor Yellow
    }
    else {
        Write-Host ('  [FALHOU]  {0}: nao foi possivel ativar' -f $name) -ForegroundColor Red
    }
}

$after = Get-StateList
Show-StateTable $after
Write-Host ''
} -Check:$Check -Enable:$Enable
