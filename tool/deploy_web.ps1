<#
.SYNOPSIS
  Web (PWA) をビルドして、公開用のファイルを置く。コミットとプッシュは自分で行う（このスクリプトは行わない）。

.DESCRIPTION
  -Target root      （既定）今の公開方法。GitHub Pages が main ブランチのルートを公開しているので、ビルドの成果物をプロジェクトのルートに上書きコピーする。
                    成果物（main.dart.js など数MB）が main の履歴に積み重なる。
  -Target gh-pages  成果物だけを別ブランチ gh-pages に置く（git worktree を使う）。main の履歴にビルド成果物が入らなくなる。
                    使う前に、GitHub の Settings → Pages → Branch を gh-pages / (root) に1度だけ変更すること。変更するまでは公開が更新されない。

  どちらも、Wasm ビルド（--wasm）。base-href は /tab2026/。

.EXAMPLE
  ./tool/deploy_web.ps1                       # ビルドして、ルートへコピー
  ./tool/deploy_web.ps1 -SkipBuild -DryRun    # ビルド済みの build/web を使い、何をするかだけ表示
  ./tool/deploy_web.ps1 -Target gh-pages      # gh-pages ブランチの作業フォルダ（../tab2026_pages）に置く
#>
param(
  [ValidateSet('root', 'gh-pages')] [string]$Target = 'root',
  [switch]$SkipBuild,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Step($msg) { Write-Host "▶ $msg" -ForegroundColor Cyan }

if (-not $SkipBuild) {
  Step 'flutter build web --release --wasm --base-href /tab2026/'
  if (-not $DryRun) { flutter build web --release --wasm --base-href /tab2026/; if ($LASTEXITCODE -ne 0) { throw 'ビルドに失敗しました' } }
}
$src = Join-Path $repo 'build/web'
if (-not (Test-Path (Join-Path $src 'index.html'))) { throw "build/web がありません（-SkipBuild を外してビルドしてください）" }

# 公開に要らないもの（ソースマップ・ビルドの記録）
$skip = @('main.dart.js.map', '.last_build_id')

if ($Target -eq 'root') {
  Step "build/web の中身を、プロジェクトのルートへ上書きコピー（$($skip -join '・') は除く）"
  Get-ChildItem $src -Force | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
    Write-Host "   $($_.Name)"
    if (-not $DryRun) { Copy-Item $_.FullName -Destination $repo -Recurse -Force }
  }
  Write-Host ''
  if ($DryRun) { Write-Host '（DryRun：何も書き換えていません）' -ForegroundColor Yellow } else { Write-Host 'コピーしました。git status で確認して、自分でコミット・プッシュしてください。' -ForegroundColor Green }
} else {
  $work = Join-Path (Split-Path -Parent $repo) 'tab2026_pages'
  Step "gh-pages の作業フォルダ: $work"
  if (-not (Test-Path $work)) {
    $hasBranch = (git branch --list gh-pages) -ne $null -and (git branch --list gh-pages).Trim() -ne ''
    if ($DryRun) { Write-Host '   （作業フォルダを作る：git worktree add）' }
    elseif ($hasBranch) { git worktree add $work gh-pages }
    else { git worktree add --orphan -b gh-pages $work }
  }
  Step '成果物を作業フォルダへコピー（古いファイルは消す。.git と .nojekyll は残す）'
  if (-not $DryRun) {
    Get-ChildItem $work -Force | Where-Object { $_.Name -notin @('.git', '.nojekyll') } | Remove-Item -Recurse -Force
    Get-ChildItem $src -Force | Where-Object { $skip -notcontains $_.Name } | ForEach-Object { Copy-Item $_.FullName -Destination $work -Recurse -Force }
    if (-not (Test-Path (Join-Path $work '.nojekyll'))) { New-Item -ItemType File (Join-Path $work '.nojekyll') | Out-Null }
  }
  Write-Host ''
  Write-Host "作業フォルダ $work で、git add -A / git commit / git push origin gh-pages を行ってください。" -ForegroundColor Green
  Write-Host '（初めてのときは、GitHub の Settings → Pages → Branch を gh-pages に変える）' -ForegroundColor Yellow
}
