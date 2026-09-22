# 如遇执行策略限制，先运行：
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"

$Url     = "https://s1y4x1.github.io/BJTU-course-assistant-main.zip"
$ZipFile = Join-Path $env:TEMP "BJTU-course-assistant-main.zip"

# 确定解压目录：文件运行时用脚本所在目录，管道运行时用当前目录
$ExtractDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

Write-Host "[1/3] 正在下载..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $Url -OutFile $ZipFile -UseBasicParsing
} catch {
    Write-Host "下载失败: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "[2/3] 正在解压到: $ExtractDir" -ForegroundColor Cyan
try {
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force
} catch {
    Write-Host "解压失败: $($_.Exception.Message)" -ForegroundColor Red
    return
}

Write-Host "[3/3] 清理临时文件..." -ForegroundColor Cyan
Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue

Write-Host "完成！解压目录：$ExtractDir\BJTU-course-assistant-main" -ForegroundColor Green