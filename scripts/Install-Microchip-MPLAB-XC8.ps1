#requires -version 5.1

[CmdletBinding()]
param(
    [string]$DestinationDirectory = "$env:ProgramData\Airlife\Installers\Microchip"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$packages = @(
    [pscustomobject]@{
        Name         = 'MPLAB X IDE 6.35'
        Uri          = 'https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/MPLABX-v6.35-windows-installer.exe'
        Referer      = 'https://www.microchip.com/en-us/tools-resources/develop/mplab-x-ide'
        FileName     = 'MPLABX-v6.35-windows-installer.exe'
        ExpectedSize = 1163506368
        InstallArguments = @(
            '--mode', 'unattended',
            '--unattendedmodeui', 'none'
        )
        DetectionPath = "$env:ProgramFiles\Microchip\MPLABX\v6.35"
    }
    [pscustomobject]@{
        Name         = 'MPLAB XC8 4.00'
        Uri          = 'https://ww1.microchip.com/downloads/aemDocuments/documents/DEV/ProductDocuments/SoftwareTools/xc8-v4.00-full-install-windows-x64-installer.exe'
        Referer      = 'https://www.microchip.com/en-us/tools-resources/develop/mplab-xc-compilers/xc8'
        FileName     = 'xc8-v4.00-full-install-windows-x64-installer.exe'
        ExpectedSize = 105996784
        InstallArguments = @(
            '--mode', 'unattended',
            '--unattendedmodeui', 'none'
        )
        DetectionPath = "$env:ProgramFiles\Microchip\xc8\v4.00"
    }
)

function Write-Log {
    param([string]$Message)
    Write-Output ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Test-MicrochipSignature {
    param([Parameter(Mandatory)][string]$Path)

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid') {
        throw "Firma Authenticode inválida para $Path. Estado: $($signature.Status)"
    }
    if (-not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'Microchip') {
        throw "El firmante de $Path no corresponde a Microchip Technology."
    }

    return $signature.SignerCertificate.Subject
}

function Install-MicrochipPackage {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$InstallerPath
    )

    if (Test-Path -LiteralPath $Package.DetectionPath) {
        Write-Log "$($Package.Name) ya está instalado."
        return
    }

    Write-Log "Instalando $($Package.Name) en modo silencioso..."
    $process = Start-Process `
        -FilePath $InstallerPath `
        -ArgumentList $Package.InstallArguments `
        -Wait `
        -PassThru

    if ($process.ExitCode -notin @(0, 3010)) {
        throw "La instalación de $($Package.Name) devolvió el código $($process.ExitCode)."
    }

    if (-not (Test-Path -LiteralPath $Package.DetectionPath)) {
        throw "El instalador terminó sin error, pero no se encontró $($Package.DetectionPath)."
    }

    if ($process.ExitCode -eq 3010) {
        Write-Log "$($Package.Name) instalado; el equipo requiere reinicio."
        $script:RestartRequired = $true
    }
    else {
        Write-Log "$($Package.Name) instalado correctamente."
    }
}

function New-DesktopShortcut {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation
    )

    $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if ([string]::IsNullOrWhiteSpace($publicDesktop)) {
        $publicDesktop = Join-Path $env:PUBLIC 'Desktop'
    }

    New-Item -ItemType Directory -Path $publicDesktop -Force | Out-Null
    $shortcutPath = Join-Path $publicDesktop "$Name.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath

    if ($Arguments) {
        $shortcut.Arguments = $Arguments
    }
    if ($WorkingDirectory) {
        $shortcut.WorkingDirectory = $WorkingDirectory
    }
    if ($IconLocation) {
        $shortcut.IconLocation = $IconLocation
    }

    $shortcut.Save()
    Write-Log "Acceso directo creado: $shortcutPath"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/138.0 Safari/537.36'
    }

    foreach ($package in $packages) {
        $uri = [uri]$package.Uri
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'ww1.microchip.com') {
            throw "Origen no autorizado para $($package.Name): $uri"
        }

        $destination = Join-Path $DestinationDirectory $package.FileName
        $temporary = "$destination.download"
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue

        Write-Log "Descargando $($package.Name) desde Microchip..."
        $downloadHeaders = $headers.Clone()
        $downloadHeaders['Referer'] = $package.Referer
        Invoke-WebRequest -Uri $package.Uri -Headers $downloadHeaders `
            -OutFile $temporary -UseBasicParsing -MaximumRedirection 0

        $file = Get-Item -LiteralPath $temporary
        if ($file.Length -ne $package.ExpectedSize) {
            throw "Tamaño inesperado para $($package.Name). Esperado: $($package.ExpectedSize); recibido: $($file.Length)."
        }

        $signer = Test-MicrochipSignature -Path $temporary
        $sha256 = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
        Move-Item -LiteralPath $temporary -Destination $destination -Force

        Write-Log "$($package.Name) descargado y validado."
        Write-Output "  Archivo: $destination"
        Write-Output "  SHA-256: $sha256"
        Write-Output "  Firmante: $signer"

        Install-MicrochipPackage `
            -Package $package `
            -InstallerPath $destination
    }

    $mplabBinDirectory = Join-Path `
        "$env:ProgramFiles\Microchip\MPLABX\v6.35\mplab_platform" `
        'bin'

    $mplabExecutable = @(
        (Join-Path $mplabBinDirectory 'mplab_ide64.exe'),
        (Join-Path $mplabBinDirectory 'mplab_ide.exe')
    ) | Where-Object {
        Test-Path -LiteralPath $_
    } | Select-Object -First 1

    if (-not $mplabExecutable) {
        throw 'MPLAB X IDE está instalado, pero no se encontró su ejecutable.'
    }

    New-DesktopShortcut `
        -Name 'MPLAB X IDE 6.35' `
        -TargetPath $mplabExecutable `
        -WorkingDirectory $mplabBinDirectory `
        -IconLocation "$mplabExecutable,0"

    $edgePath = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object {
        Test-Path -LiteralPath $_
    } | Select-Object -First 1

    if ($edgePath) {
        New-DesktopShortcut `
            -Name 'AutoCAD Web' `
            -TargetPath $edgePath `
            -Arguments '--app=https://web.autocad.com/' `
            -WorkingDirectory (Split-Path -Parent $edgePath) `
            -IconLocation "$edgePath,0"
    }
    else {
        $publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        if ([string]::IsNullOrWhiteSpace($publicDesktop)) {
            $publicDesktop = Join-Path $env:PUBLIC 'Desktop'
        }
        $autoCadUrl = Join-Path $publicDesktop 'AutoCAD Web.url'
        Set-Content -LiteralPath $autoCadUrl -Encoding ASCII -Value @(
            '[InternetShortcut]'
            'URL=https://web.autocad.com/'
        )
        Write-Log "Acceso directo creado: $autoCadUrl"
    }

    Write-Log 'Descarga, instalación y creación de accesos directos completadas.'

    if ($script:RestartRequired) {
        Write-Warning 'Uno de los instaladores solicitó reiniciar el equipo.'
        exit 3010
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    Get-ChildItem -LiteralPath $DestinationDirectory -Filter '*.download' `
        -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
