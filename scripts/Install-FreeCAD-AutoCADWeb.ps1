#requires -version 5.1

[CmdletBinding()]
param(
    [string]$InstallerDirectory = "$env:ProgramData\Airlife\Installers\FreeCAD"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$freeCadVersion = '1.1.2'
$freeCadUri = 'https://github.com/FreeCAD/FreeCAD/releases/download/1.1.2/FreeCAD_1.1.2-Windows-x86_64-py311-installer.exe'
$freeCadFileName = 'FreeCAD_1.1.2-Windows-x86_64-py311-installer.exe'
$freeCadSha256 = 'A5D9D829C10A6074620DC4CA52CA13E71D87D866E0CAF4B737172FFB4F94BEC9'

function Write-Log {
    param([string]$Message)
    Write-Output ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
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
    New-Item -ItemType Directory -Path $InstallerDirectory -Force | Out-Null

    $installerPath = Join-Path $InstallerDirectory $freeCadFileName
    $temporaryPath = "$installerPath.download"

    $existingFreeCad = Get-ChildItem `
        -Path "$env:ProgramFiles\FreeCAD*" `
        -Filter 'FreeCAD.exe' `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '\\bin\\FreeCAD\.exe$'
        } |
        Select-Object -First 1

    if (-not $existingFreeCad) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        Write-Log "Descargando FreeCAD $freeCadVersion desde el repositorio oficial..."

        Invoke-WebRequest `
            -Uri $freeCadUri `
            -OutFile $temporaryPath `
            -UseBasicParsing `
            -MaximumRedirection 5 `
            -Headers @{ 'User-Agent' = 'Airlife-Pulseway-Installer' }

        $actualHash = (
            Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256
        ).Hash

        if ($actualHash -ne $freeCadSha256) {
            throw "SHA-256 incorrecto para FreeCAD. Esperado: $freeCadSha256; recibido: $actualHash"
        }

        $signature = Get-AuthenticodeSignature -FilePath $temporaryPath
        if ($signature.Status -ne 'Valid') {
            throw "La firma Authenticode de FreeCAD no es válida. Estado: $($signature.Status)"
        }

        Move-Item -LiteralPath $temporaryPath -Destination $installerPath -Force

        Write-Log "Instalando FreeCAD $freeCadVersion silenciosamente..."
        $process = Start-Process `
            -FilePath $installerPath `
            -ArgumentList '/S' `
            -Wait `
            -PassThru

        if ($process.ExitCode -notin @(0, 3010)) {
            throw "La instalación de FreeCAD devolvió el código $($process.ExitCode)."
        }

        if ($process.ExitCode -eq 3010) {
            $script:RestartRequired = $true
        }
    }
    else {
        Write-Log "FreeCAD ya está instalado en $($existingFreeCad.FullName)."
    }

    $freeCadExecutable = Get-ChildItem `
        -Path "$env:ProgramFiles\FreeCAD*" `
        -Filter 'FreeCAD.exe' `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '\\bin\\FreeCAD\.exe$'
        } |
        Select-Object -First 1

    if (-not $freeCadExecutable) {
        throw 'FreeCAD no quedó instalado o no se encontró FreeCAD.exe.'
    }

    New-DesktopShortcut `
        -Name "FreeCAD $freeCadVersion" `
        -TargetPath $freeCadExecutable.FullName `
        -WorkingDirectory $freeCadExecutable.DirectoryName `
        -IconLocation "$($freeCadExecutable.FullName),0"

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

        $urlPath = Join-Path $publicDesktop 'AutoCAD Web.url'
        Set-Content -LiteralPath $urlPath -Encoding ASCII -Value @(
            '[InternetShortcut]'
            'URL=https://web.autocad.com/'
        )
        Write-Log "Acceso directo creado: $urlPath"
    }

    Write-Log 'FreeCAD y el acceso a AutoCAD Web quedaron configurados.'

    if ($script:RestartRequired) {
        Write-Warning 'FreeCAD solicitó reiniciar el equipo.'
        exit 3010
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
