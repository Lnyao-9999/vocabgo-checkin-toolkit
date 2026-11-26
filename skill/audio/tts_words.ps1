param(
  [string]$Words = 'beam,midst,groan,compliment',
  [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\templates' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
$en = $syn.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'en*' } | Select-Object -First 1
if ($en) { $syn.SelectVoice($en.VoiceInfo.Name); "voice: $($en.VoiceInfo.Name)" } else { "WARN: no en-US TTS voice installed" }
$made = 0
foreach ($w in ($Words -split ',')) {
  $w = $w.Trim()
  if (-not $w) { continue }
  $path = Join-Path $OutDir ("$w.wav")
  $syn.SetOutputToWaveFile($path, $fmt)
  $syn.Speak($w)
  $syn.SetOutputToNull()
  $made++
  "wrote $path"
}
$syn.Dispose()
"templates written: $made"
