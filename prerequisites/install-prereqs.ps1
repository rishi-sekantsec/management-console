[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorLine {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ArchitectureName {
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $archCode = [int]$processor.Architecture
    switch ($archCode) {
        0 { return "x86" }
        5 { return "arm" }
        9 { return "x64" }
        12 { return "arm64" }
        default { return "unknown" }
    }
}

function Ensure-Elevated {
    if (Test-IsAdmin) {
        return
    }

    Write-Info "Re-launching with Administrator privileges..."
    $arguments = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", "`"$PSCommandPath`""
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs | Out-Null
    exit 0
}

function Ensure-Tls12 {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function Ensure-Chocolatey {
    if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        return
    }

    Write-Info "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $installScript = Invoke-WebRequest -UseBasicParsing "https://community.chocolatey.org/install.ps1"
    Invoke-Expression $installScript.Content
}

function Refresh-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath) -join ";"
}

function Install-ChocoPackage {
    param([string]$PackageName)

    Write-Info "Installing package '$PackageName'..."
    choco upgrade $PackageName -y --no-progress | Out-Host
}

function Find-DockerDesktopExe {
    $candidates = @(
        "$Env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Enable-DockerAutostart {
    param([string]$DockerDesktopExe)

    if ([string]::IsNullOrWhiteSpace($DockerDesktopExe)) {
        return
    }

    Write-Info "Configuring Docker Desktop to start on sign-in..."
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name "Docker Desktop" -Value "`"$DockerDesktopExe`"" -PropertyType String -Force | Out-Null
}

function Ensure-DockerService {
    if (-not (Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue)) {
        Write-WarnLine "Docker Desktop service 'com.docker.service' was not found yet."
        return
    }

    Write-Info "Setting Docker service to Automatic..."
    Set-Service -Name "com.docker.service" -StartupType Automatic
    if ((Get-Service -Name "com.docker.service").Status -ne "Running") {
        Start-Service -Name "com.docker.service"
    }
}

function Start-DockerDesktop {
    param([string]$DockerDesktopExe)

    if ([string]::IsNullOrWhiteSpace($DockerDesktopExe)) {
        throw "Docker Desktop executable could not be found after installation."
    }

    Write-Info "Starting Docker Desktop..."
    Start-Process -FilePath $DockerDesktopExe | Out-Null
}

function Wait-ForDocker {
    Write-Info "Waiting for Docker to become ready..."
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if (Get-Command docker.exe -ErrorAction SilentlyContinue) {
            try {
                docker info | Out-Null
                return
            } catch {
            }
        }
        Start-Sleep -Seconds 5
    }

    throw "Docker Desktop did not become ready within the expected time."
}

function Verify-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Expected command '$Name' is not available after installation."
    }
}

function Install-Prerequisites {
    $packages = @(
        "git",
        "wget",
        "curl",
        "openssl.light",
        "docker-desktop"
    )

    foreach ($package in $packages) {
        Install-ChocoPackage -PackageName $package
    }
}

Ensure-Elevated
Ensure-Tls12

$os = Get-CimInstance Win32_OperatingSystem
$architecture = Get-ArchitectureName
$is64Bit = [Environment]::Is64BitOperatingSystem

Write-Info "Detected OS        : $($os.Caption)"
Write-Info "Detected version   : $($os.Version)"
Write-Info "Detected arch      : $architecture"

if (-not $is64Bit) {
    Write-ErrorLine "Docker Desktop requires a 64-bit Windows system."
    exit 1
}

Ensure-Chocolatey
Refresh-SessionPath
Install-Prerequisites
Refresh-SessionPath

$gitCmdPath = "$Env:ProgramFiles\Git\cmd"
$dockerCliPath = "$Env:ProgramFiles\Docker\Docker\resources\bin"

foreach ($candidatePath in @($gitCmdPath, $dockerCliPath)) {
    if ((Test-Path $candidatePath) -and ($env:Path -notlike "*$candidatePath*")) {
        $env:Path = "$env:Path;$candidatePath"
    }
}

$dockerDesktopExe = Find-DockerDesktopExe
Enable-DockerAutostart -DockerDesktopExe $dockerDesktopExe
Ensure-DockerService
Start-DockerDesktop -DockerDesktopExe $dockerDesktopExe
Wait-ForDocker

Verify-Command -Name "git.exe"
Verify-Command -Name "wget.exe"
Verify-Command -Name "curl.exe"
Verify-Command -Name "openssl.exe"
Verify-Command -Name "docker.exe"

Write-Info "Verifying Docker Compose..."
docker compose version | Out-Host

Write-Host "[SUCCESS] Prerequisites are installed." -ForegroundColor Green
Write-WarnLine "If Docker Desktop prompts for WSL/Hyper-V or license acceptance, complete that wizard once and then re-run the installer if needed."
