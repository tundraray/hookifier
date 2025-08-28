#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell script to compile MQL5 Expert Advisor and rename to versioned filename
.DESCRIPTION
    This script compiles MQL5 files using MetaEditor and creates versioned copies
    based on the version property in the source file
.PARAMETER SourceFile
    Path to the source MQL5 file to compile (optional, auto-detected if not specified)
.PARAMETER MetaEditorPath
    Path to MetaEditor executable (optional, auto-detected if not specified)
.PARAMETER WebhookURL
    Override webhook URL in the source file for this build
.PARAMETER BuildConfig
    Build configuration name (default, production, test, dev, etc.)
.PARAMETER NoBackup
    Skip creating backup of original source file before modification
.EXAMPLE
    .\compile.ps1
    .\compile.ps1 -SourceFile ".\Hookifier.mq5"
    .\compile.ps1 -WebhookURL "https://my-test-webhook.com/endpoint"
    .\compile.ps1 -BuildConfig "production" -WebhookURL "https://prod-webhook.com/endpoint"
    .\compile.ps1 -SourceFile ".\Hookifier.mq5" -MetaEditorPath "C:\Custom\Path\metaeditor64.exe"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SourceFile,
    
    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath,
    
    [Parameter(Mandatory=$false)]
    [string]$WebhookURL,
    
    [Parameter(Mandatory=$false)]
    [string]$BuildConfig = "default",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoBackup
)

# Function for logging
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch($Level) {
            "ERROR" { "Red" }
            "WARN"  { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
}

# Auto-detect source file if not specified
if (-not $SourceFile) {
    # Look for .mq5 files in current directory
    $mq5Files = Get-ChildItem -Path "." -Filter "*.mq5" | Sort-Object Name
    
    if ($mq5Files.Count -eq 0) {
        Write-Log "No MQL5 files found in current directory" "ERROR"
        Write-Log "Please specify -SourceFile parameter or run from directory with .mq5 files" "ERROR"
        exit 1
    } elseif ($mq5Files.Count -eq 1) {
        $SourceFile = $mq5Files[0].FullName
        Write-Log "Auto-detected source file: $($mq5Files[0].Name)"
    } else {
        Write-Log "Multiple MQL5 files found in current directory:" "WARN"
        $mq5Files | ForEach-Object { Write-Log "  - $($_.Name)" "WARN" }
        
        # Try to find main file (same name as directory or containing #property)
        $currentDir = Split-Path (Get-Location) -Leaf
        $mainFile = $mq5Files | Where-Object { $_.BaseName -eq $currentDir }
        
        if ($mainFile) {
            $SourceFile = $mainFile.FullName
            Write-Log "Auto-selected main file: $($mainFile.Name)" "SUCCESS"
        } else {
            # Use the first file as fallback
            $SourceFile = $mq5Files[0].FullName
            Write-Log "Using first file: $($mq5Files[0].Name)" "WARN"
        }
    }
}

# Check source file exists
if (-not (Test-Path $SourceFile)) {
    Write-Log "Source file not found: $SourceFile" "ERROR"
    exit 1
}

$SourceFile = Resolve-Path $SourceFile

# Check for spaces in path (MetaEditor issue)
if ($SourceFile.ToString().Contains(" ")) {
    Write-Log "ERROR! File path contains SPACES! MetaEditor cannot compile!" "ERROR"
    Write-Log "Path: $SourceFile" "ERROR"
    Write-Log "Please move files to path without spaces" "ERROR"
    exit 1
}

Write-Log "Source file: $SourceFile"

# Auto-detect MetaEditor if path not specified
if (-not $MetaEditorPath) {
    $possiblePaths = @(
        "${env:ProgramFiles}\MetaTrader 5\metaeditor64.exe",
        "${env:ProgramFiles(x86)}\MetaTrader 5\metaeditor64.exe",
        "C:\Program Files\MetaTrader 5\metaeditor64.exe",
        "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $MetaEditorPath = $path
            break
        }
    }
    
    if (-not $MetaEditorPath) {
        Write-Log "MetaEditor not found in standard paths" "ERROR"
        Write-Log "Please specify path to MetaEditor with -MetaEditorPath parameter" "ERROR"
        exit 1
    }
}

Write-Log "MetaEditor found: $MetaEditorPath"

# Extract version from source file
try {
    $content = Get-Content $SourceFile -Encoding UTF8
    $versionLine = $content | Where-Object { $_ -match '#property\s+version\s+"([^"]+)"' }
    
    if ($versionLine) {
        $version = $matches[1]
        Write-Log "Found version: $version"
    } else {
        Write-Log "Version not found in file, using timestamp" "WARN"
        $version = Get-Date -Format "yyyy.MM.dd.HHmm"
    }
} catch {
    Write-Log "Error reading file: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Get filename info
$sourceInfo = Get-Item $SourceFile
$baseName = $sourceInfo.BaseName
$sourceDir = $sourceInfo.Directory.FullName

# Handle build parameters
$buildSuffix = ""
$tempSourceFile = $SourceFile
$needsCleanup = $false

if ($WebhookURL -or $BuildConfig -ne "default") {
    if ($BuildConfig -ne "default") {
        $buildSuffix = "-$BuildConfig"
    }
    
    # Create temporary source file with modifications
    $tempSourceFile = Join-Path $sourceDir "$baseName.build.mq5"
    $needsCleanup = $true
    
    $modifiedContent = $content
    
    if ($WebhookURL) {
        Write-Log "Setting webhook URL: $WebhookURL"
        $modifiedContent = $modifiedContent -replace 'input\s+string\s+WebhookURL\s*=\s*"[^"]*"', "input string   WebhookURL = `"$WebhookURL`""
    }
    
    # Write modified content to temporary file
    $modifiedContent | Out-File -FilePath $tempSourceFile -Encoding UTF8
    Write-Log "Created temporary build file: $($baseName).build.mq5"
}

# Create versioned name
$versionedName = "$baseName-$version$buildSuffix"

# Code is already in Advisors folder, compile to current directory
$currentDir = $sourceDir

# If using temp file, the compiled file will have temp name
$tempBaseName = if ($needsCleanup) { "$baseName.build" } else { $baseName }
$compiledFile = Join-Path $currentDir "$tempBaseName.ex5"
$finalCompiledFile = Join-Path $currentDir "$baseName.ex5"
$versionedFile = Join-Path $currentDir "$versionedName.ex5"

# Stop MetaTrader terminal to ensure it sees new compiled version
Write-Log "Stopping MetaTrader terminal if running..."
Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Id -gt 0} | Stop-Process

Write-Log "Compiling file..."
Write-Log "Source: $($sourceInfo.Name)"
Write-Log "Output: $versionedName.ex5"

# Compile
try {
    $logFile = "$tempSourceFile.log"
    $mql5IncludePath = Split-Path (Split-Path $sourceDir -Parent) -Parent
    $processArgs = @("/compile:`"$tempSourceFile`"", "/log:`"$logFile`"", "/inc:`"$mql5IncludePath`"", "/optimize")
    
    Write-Log "Running: `"$MetaEditorPath`" $($processArgs -join ' ')"
    
    $process = Start-Process -FilePath $MetaEditorPath -ArgumentList $processArgs -Wait -PassThru -NoNewWindow | Out-Null
    
    # Read and process compilation log
    if (Test-Path $logFile) {
        $logContent = Get-Content -Path $logFile -Encoding UTF8 | Where-Object {$_ -ne ""} | Select-Object -Skip 1
        
        # Determine compilation result color
        $logColor = "Red"
        $compilationSuccessful = $false
        $logContent | ForEach-Object { 
            if ($_.Contains("0 errors, 0 warnings") -or $_.Contains("0 error(s), 0 warning(s)")) { 
                $logColor = "Green"
                $compilationSuccessful = $true
            } 
        }
        
        # Display compilation results
        Write-Log "Compilation Results:" $(if($compilationSuccessful) {"SUCCESS"} else {"ERROR"})
        $logContent | ForEach-Object {
            # Skip information lines when compilation was successful
            if (-Not $_.Contains("information:") -or -Not $compilationSuccessful) {
                Write-Host "  $_" -ForegroundColor $logColor
            }
        }
        
        if (-Not $compilationSuccessful) {
            # Cleanup temp file on compilation failure
            if ($needsCleanup -and (Test-Path $tempSourceFile)) {
                Remove-Item $tempSourceFile -Force -ErrorAction SilentlyContinue
                Write-Log "Cleaned up temporary file"
            }
            exit 1
        }
    } else {
        Write-Log "Compilation log file not found: $logFile" "ERROR"
        exit 1
    }
} catch {
    Write-Log "Error starting compiler: $($_.Exception.Message)" "ERROR"
    
    # Cleanup temp file on error
    if ($needsCleanup -and (Test-Path $tempSourceFile)) {
        Remove-Item $tempSourceFile -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned up temporary file"
    }
    exit 1
}

# Check compiled file exists
if (Test-Path $compiledFile) {
    Write-Log "Found compiled file: $(Split-Path $compiledFile -Leaf)" "SUCCESS"
    
    # Rename compiled file to versioned name
    try {
        Move-Item $compiledFile $versionedFile -Force
        Write-Log "Created versioned file: $versionedName.ex5" "SUCCESS"
        
        # Show file info
        $versionedInfo = Get-Item $versionedFile
        
        Write-Log "File information:"
        Write-Log "  Versioned: $($versionedInfo.Name) ($($versionedInfo.Length) bytes)"
        Write-Log "  Location: $($versionedInfo.Directory.FullName)"
        
        # Optional: show hash for integrity check
        $hash = Get-FileHash $versionedFile -Algorithm SHA256
        Write-Log "  SHA256: $($hash.Hash.Substring(0,16))..."
        
    } catch {
        Write-Log "Error creating versioned copy: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-Log "Compiled file not found: $compiledFile" "ERROR"
    Write-Log "Compilation may have failed with errors" "ERROR"
    exit 1
}

# Cleanup temporary file
if ($needsCleanup -and (Test-Path $tempSourceFile)) {
    try {
        Remove-Item $tempSourceFile -Force
        Write-Log "Cleaned up temporary file: $(Split-Path $tempSourceFile -Leaf)"
    } catch {
        Write-Log "Warning: Could not remove temporary file" "WARN"
    }
}

Write-Log "Script completed successfully" "SUCCESS"
Write-Log "Results:"
Write-Log "  * Created version: $versionedName.ex5"
if ($BuildConfig -ne "default") {
    Write-Log "  * Build config: $BuildConfig"
}
if ($WebhookURL) {
    Write-Log "  * Custom webhook: $WebhookURL"
}

# Offer to restart MetaTrader terminal
$restart = Read-Host "Restart MetaTrader terminal? (y/N)"
if ($restart -eq "y" -or $restart -eq "Y") {
    Write-Log "Restarting MetaTrader terminal..."
    try {
        & "$($MetaEditorPath.Replace("metaeditor64.exe", "terminal64.exe"))" | Out-Null
        Write-Log "MetaTrader terminal started"
    } catch {
        Write-Log "Could not start MetaTrader terminal" "WARN"
    }
}