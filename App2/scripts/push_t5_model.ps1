$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$modelDir = Join-Path $projectRoot "assets\models"
$remoteDir = "/sdcard/Android/data/com.example.sign_language_app/files/synapse_model_sync"

$files = @(
  "t5_encoder.onnx",
  "t5_decoder.onnx",
  "t5_vocab.txt",
  "t5_config.txt"
)

Write-Host "Pushing T5 model files to phone sync folder..."
adb shell "mkdir -p $remoteDir" | Out-Null

foreach ($file in $files) {
  $localPath = Join-Path $modelDir $file
  if (-not (Test-Path $localPath)) {
    throw "Missing file: $localPath"
  }
  Write-Host "  -> $file"
  adb push $localPath "$remoteDir/$file" | Out-Null
}

Write-Host ""
Write-Host "Model sync complete."
Write-Host "The app will auto-detect the new model within a few seconds."
Write-Host "Remote folder: $remoteDir"
