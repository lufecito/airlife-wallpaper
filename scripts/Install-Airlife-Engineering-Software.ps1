#requires -version 5.1

[CmdletBinding()]
param(
    [string]$DownloadDirectory = "$env:ProgramData\Airlife\Pulseway\EngineeringSoftware",
    [string]$RepositoryBranch = 'main'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repositoryRoot = "https://raw.githubusercontent.com/lufecito/airlife-wallpaper/$RepositoryBranch/scripts"
$restartRequired = $false

$installers = @(
    [pscustomobject]@{
        Name   = 'MPLAB X IDE 6.35 y MPLAB XC8 4.00'
        File   = 'Install-Microchip-MPLAB-XC8.ps1'
        Sha256 = 'EC5F3E2E92D6C6C97AA2F42558335FDB612753FE7D54AD7E88207F167921CEFB'
    }
    [pscustomobject]@{
        Name   = 'FreeCAD 1.1.2 y AutoCAD Web'
        File   = 'Install-FreeCAD-AutoCADWeb.ps1'
        Sha256 = '846A053696FF6DDFBFD1DC641B49B92D1D16A79CE813677791E581E785CBE6D0'
    }
)

function Write-Log {
    param([string]$Message)
    Write-Output ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Este despliegue debe ejecutarse como administrador o LocalSystem.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null

    foreach ($installer in $installers) {
        $uri = "$repositoryRoot/$($installer.File)"
        $destination = Join-Path $DownloadDirectory $installer.File
        $temporary = "$destination.download"

        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Write-Log "Descargando $($installer.Name)..."

        Invoke-WebRequest `
            -Uri $uri `
            -OutFile $temporary `
            -UseBasicParsing `
            -MaximumRedirection 3 `
            -Headers @{ 'User-Agent' = 'Airlife-Pulseway' }

        $actualHash = (
            Get-FileHash -LiteralPath $temporary -Algorithm SHA256
        ).Hash

        if ($actualHash -ne $installer.Sha256) {
            throw "SHA-256 incorrecto para $($installer.File). Esperado: $($installer.Sha256); recibido: $actualHash"
        }

        Move-Item -LiteralPath $temporary -Destination $destination -Force
        Write-Log "Ejecutando $($installer.Name)..."

        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoLogo'
                '-NoProfile'
                '-NonInteractive'
                '-ExecutionPolicy'
                'Bypass'
                '-File'
                "`"$destination`""
            ) `
            -Wait `
            -PassThru

        if ($process.ExitCode -eq 3010) {
            $restartRequired = $true
        }
        elseif ($process.ExitCode -ne 0) {
            throw "$($installer.Name) devolvió el código $($process.ExitCode)."
        }

        Write-Log "$($installer.Name) finalizado."
    }

    Write-Log 'Despliegue de software de ingeniería completado.'

    if ($restartRequired) {
        Write-Warning 'Uno o más instaladores requieren reiniciar el equipo.'
        exit 3010
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    Get-ChildItem `
        -LiteralPath $DownloadDirectory `
        -Filter '*.download' `
        -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
