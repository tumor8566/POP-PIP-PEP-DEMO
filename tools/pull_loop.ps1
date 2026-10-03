# pull_loop.ps1 — 近实时从 GitHub 拉取最新代码
# 用法:
#   1) 先把本仓库克隆到你的工程目录(或在该目录打开 PowerShell)
#   2) 右键本文件 -> 用 PowerShell 运行, 或在终端执行:
#        powershell -ExecutionPolicy Bypass -File pull_loop.ps1
#   脚本每 3 秒拉取一次; 拉着不放即可在对战里实时看到我推上来的改动。
#   按 Ctrl+C 退出。

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== PPP 工程自动拉取 (每 3 秒) ===" -ForegroundColor Cyan
Write-Host "在 Godot 编辑器保持打开的状态下, 拉取后外部改动会自动重载。" -ForegroundColor Gray
Write-Host "按 Ctrl+C 停止。" -ForegroundColor Gray

while ($true) {
    try {
        $out = git pull --ff-only 2>&1
        $line = $out | Out-String
        if ($line -match "Already up to date") {
            # 无更新, 静默
        } else {
            Write-Host ("[$(Get-Date -Format 'HH:mm:ss')] " + ($line -replace "`n|`r", " ")) -ForegroundColor Green
        }
    } catch {
        Write-Host ("[$(Get-Date -Format 'HH:mm:ss')] pull 失败: " + $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Seconds 3
}
