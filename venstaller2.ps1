<#
.SYNOPSIS
Vencord Custom Injection Script - PowerShell Edition

.DESCRIPTION
Downloads all build artifacts from your Vencord release and installs them

.PARAMETER Branch
Discord branch to install to (stable, ptb, canary)

.EXAMPLE
.\VencordInject.ps1 -Branch canary
#>

param(
    [ValidateSet("stable", "ptb", "canary")]
    [string]$Branch = "stable"
)

# Define platform variables for Windows PowerShell compatibility
if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
    $IsWindows = $env:OS -eq 'Windows_NT'
}
if (-not (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue)) {
    $IsMacOS = $false
}
if (-not (Get-Variable -Name IsLinux -ErrorAction SilentlyContinue)) {
    $IsLinux = $false
}

# Custom Configuration - Update with your repository details
$VencordRepo = "NatsukashiiOwU/Vencord"
$InstallerRepo = "Vencord/Installer"
$BuildTag = "natsukashii-vencord-dev"  # Your custom build tag

# GitHub API URL for your release
$ReleaseApiUrl = "https://api.github.com/repos/$VencordRepo/releases/tags/$BuildTag"

# CORRECTED: Use the standard Vencord user data directory
$VencordUserDataDir = if ($IsWindows) {
    Join-Path $env:APPDATA "Vencord"
} elseif ($IsMacOS) {
    Join-Path $env:HOME "Library" "Application Support" "Vencord"
} else {
    Join-Path $env:HOME ".config" "Vencord"
}

function Get-InstallerFilename {
    if ($IsWindows) { return "VencordInstallerCli.exe" }
    if ($IsMacOS)   { return "VencordInstaller.MacOS.zip" }
    if ($IsLinux)   { return "VencordInstallerCli-linux" }
    throw "Unsupported platform" 
}

function Get-DistPath {
    return Join-Path $VencordUserDataDir "dist"
}

function Get-InstallerPath {
    $distDir = Get-DistPath
    return Join-Path $distDir "Installer"
}

function Ensure-Directory {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Host "Path is null or empty in Ensure-Directory" -ForegroundColor Red
        return
    }
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-GitHubReleaseAssets {
    try {
        $headers = @{
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "VencordInjector"
        }
        
        # Add authentication if available
        if ($env:GITHUB_TOKEN) {
            $headers["Authorization"] = "token $env:GITHUB_TOKEN"
        }
        
        $response = Invoke-RestMethod -Uri $ReleaseApiUrl -Headers $headers
        return $response.assets
    }
    catch {
        Write-Host "Failed to get release assets: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Download-ReleaseAssets {
    $assets = Get-GitHubReleaseAssets
    if (-not $assets) {
        return $false
    }
    
    $distDir = Get-DistPath
    Ensure-Directory -Path $distDir
    
    $success = $true
    foreach ($asset in $assets) {
        $outputPath = Join-Path $distDir $asset.name
        $url = $asset.browser_download_url
        
        try {
            Write-Host "Downloading $($asset.name) from $url..." -ForegroundColor Cyan
            # Use -OutFile to handle HTTP errors consistently across PowerShell versions
            Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $outputPath -ErrorAction Stop
            Write-Host "Downloaded $($asset.name) to $outputPath" -ForegroundColor Green
        }
        catch {
            Write-Host "Error downloading $($asset.name): $($_.Exception.Message)" -ForegroundColor Red
            $success = $false
        }
    }
    
    return $success
}

function Download-Installer {
    $filename = Get-InstallerFilename
    $installerDir = Get-InstallerPath
    
    # Handle null path before using it
    if (-not $installerDir) {
        Write-Host "Installer directory path is null" -ForegroundColor Red
        return $null
    }
    
    Ensure-Directory -Path $installerDir
    
    $outputFile = Join-Path $installerDir $filename
    
    if ($IsMacOS) {
        $outputFile = Join-Path $installerDir "VencordInstaller"
    }
    
    # Skip download if installer already exists
    if (Test-Path $outputFile) {
        Write-Host "Installer already exists, skipping download" -ForegroundColor Green
        return $outputFile
    }
    
    $url = "https://github.com/$InstallerRepo/releases/latest/download/$filename"
    
    try {
        Write-Host "Downloading installer from $url..." -ForegroundColor Cyan
        # Use -OutFile to handle HTTP errors consistently
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $outputFile -ErrorAction Stop
        
        # Post-download processing
        if ($IsMacOS) {
            Write-Host "Setting executable permissions..." -ForegroundColor Cyan
            chmod +x $outputFile
            
            Write-Host "Overriding security policy..." -ForegroundColor Cyan
            try {
                & sudo spctl --add $outputFile --label "Vencord Installer"
                & sudo xattr -d com.apple.quarantine $outputFile
            } catch {
                Write-Host "Security policy override might have failed, continuing anyway..." -ForegroundColor Yellow
            }
        }
        elseif ($IsLinux) {
            chmod +x $outputFile
        }
        
        Write-Host "Installer downloaded successfully to $outputFile" -ForegroundColor Green
        return $outputFile
    } catch {
        Write-Host "Error downloading installer: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Run-Installer {
    param([string]$installerPath)
    
    # Prepare arguments and environment
    $args = @()
    if ($Branch) { $args += "--branch", $Branch }
    
    $envVars = @{
        "VENCORD_USER_DATA_DIR" = $VencordUserDataDir
        "VENCORD_DEV_INSTALL" = "1"
    }
    
    Write-Host "Running installer with parameters:" -ForegroundColor Cyan
    Write-Host "  Installer: $installerPath" -ForegroundColor Cyan
    Write-Host "  Arguments: $($args -join ' ')" -ForegroundColor Cyan
    Write-Host "  Vencord build tag: $BuildTag" -ForegroundColor Cyan
    Write-Host "  Environment:" -ForegroundColor Cyan
    Write-Host "    VENCORD_USER_DATA_DIR = $VencordUserDataDir" -ForegroundColor Cyan
    Write-Host "    VENCORD_DEV_INSTALL = 1" -ForegroundColor Cyan
    
    # Run the installer
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $installerPath
        $processInfo.Arguments = $args
        $processInfo.UseShellExecute = $false
        
        foreach ($key in $envVars.Keys) {
            $processInfo.EnvironmentVariables[$key] = $envVars[$key]
        }
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $process.WaitForExit()
        
        if ($process.ExitCode -ne 0) {
            Write-Host "Installer exited with error code $($process.ExitCode)" -ForegroundColor Red
            exit $process.ExitCode
        }
        
        Write-Host "Installation completed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Failed to run installer: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Main execution
Write-Host @"
    
███████╗███████╗███╗   ██╗ ██████╗ ██████╗ ██████╗ 
██╔════╝██╔════╝████╗  ██║██╔═══██╗██╔══██╗██╔══██╗
█████╗  █████╗  ██╔██╗ ██║██║   ██║██████╔╝██║  ██║
██╔══╝  ██╔══╝  ██║╚██╗██║██║   ██║██╔══██╗██║  ██║
███████╗███████╗██║ ╚████║╚██████╔╝██║  ██║██████╔╝
╚══════╝╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ 
                                                   
 Custom Vencord Injection Script
 Vencord Repo: https://github.com/$VencordRepo
 Installer Repo: https://github.com/$InstallerRepo
 Build Tag: $BuildTag
 Branch: $Branch
 Platform: $($PSVersionTable.OS)
 PowerShell Version: $($PSVersionTable.PSVersion)
 Vencord User Data Dir: $VencordUserDataDir

"@ -ForegroundColor Cyan

# Ensure the Vencord user data directory exists
Ensure-Directory -Path $VencordUserDataDir

# Download all release assets
Write-Host "Downloading all build artifacts from release $BuildTag..." -ForegroundColor Cyan
if (-not (Download-ReleaseAssets)) {
    Write-Host "Failed to download Vencord build artifacts, exiting..." -ForegroundColor Red
    exit 1
}

# List downloaded files
Write-Host "`nDownloaded artifacts:" -ForegroundColor Cyan
Get-ChildItem (Get-DistPath) | ForEach-Object {
    Write-Host "  - $($_.Name) ($([Math]::Round($_.Length / 1MB, 2)) MB)" -ForegroundColor Cyan
}

# Download installer
$installerPath = Download-Installer
if (-not $installerPath) {
    Write-Host "Failed to obtain installer, exiting..." -ForegroundColor Red
    exit 1
}

# Verify files exist
if (-not (Test-Path $installerPath)) {
    Write-Host "Installer not found at: $installerPath" -ForegroundColor Red
    exit 1
}

if (-not (Get-ChildItem (Get-DistPath))) {
    Write-Host "No build artifacts found in dist directory" -ForegroundColor Red
    exit 1
}

# Run installation
Run-Installer -installerPath $installerPath

# Final message
Write-Host @"

✅ Process completed!
Restart Discord for changes to take effect.

Custom Vencord build from $BuildTag has been installed:
https://github.com/$VencordRepo/releases/tag/$BuildTag

Files are located at:
$VencordUserDataDir

Press any key to exit...
"@ -ForegroundColor Green

$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")