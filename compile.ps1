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
.EXAMPLE
    .\compile.ps1
    .\compile.ps1 -SourceFile ".\Hookifier.mq5"
    .\compile.ps1 -SourceFile ".\Hookifier.mq5" -MetaEditorPath "C:\Custom\Path\metaeditor64.exe"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SourceFile,
    
    [Parameter(Mandatory=$false)]
    [string]$MetaEditorPath
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

# Create versioned name
$versionedName = "$baseName-$version"
$compiledFile = Join-Path $sourceDir "$baseName.ex5"
$versionedFile = Join-Path $sourceDir "$versionedName.ex5"

Write-Log "Compiling file..."
Write-Log "Source: $($sourceInfo.Name)"
Write-Log "Output: $versionedName.ex5"

# Compile
try {
    $processArgs = @("/compile", "`"$SourceFile`"")
    
    Write-Log "Running: $MetaEditorPath $($processArgs -join ' ')"
    
    $process = Start-Process -FilePath $MetaEditorPath -ArgumentList $processArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Log "Compilation completed successfully" "SUCCESS"
    } else {
        Write-Log "Compilation failed with exit code: $($process.ExitCode)" "ERROR"
        
        # Try to find error log
        $logDir = Join-Path (Split-Path $sourceDir -Parent) "Logs"
        if (Test-Path $logDir) {
            $todayLog = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd').log"
            if (Test-Path $todayLog) {
                Write-Log "Check log: $todayLog" "WARN"
                # Show last log lines
                $lastLines = Get-Content $todayLog -Tail 10 -Encoding UTF8
                Write-Log "Last log lines:" "WARN"
                $lastLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
            }
        }
        exit $process.ExitCode
    }
} catch {
    Write-Log "Error starting compiler: $($_.Exception.Message)" "ERROR"
    exit 1
}

# Check compiled file exists
if (Test-Path $compiledFile) {
    Write-Log "Found compiled file: $($sourceInfo.BaseName).ex5" "SUCCESS"
    
    # Create versioned copy
    try {
        Copy-Item $compiledFile $versionedFile -Force
        Write-Log "Created versioned copy: $versionedName.ex5" "SUCCESS"
        
        # Show file info
        $compiledInfo = Get-Item $compiledFile
        $versionedInfo = Get-Item $versionedFile
        
        Write-Log "File information:"
        Write-Log "  Main: $($compiledInfo.Name) ($($compiledInfo.Length) bytes, modified: $($compiledInfo.LastWriteTime))"
        Write-Log "  Versioned: $($versionedInfo.Name) ($($versionedInfo.Length) bytes)"
        
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

Write-Log "Script completed successfully" "SUCCESS"
Write-Log "Results:"
Write-Log "  * Compiled: $baseName.ex5"
Write-Log "  * Created version: $versionedName.ex5"