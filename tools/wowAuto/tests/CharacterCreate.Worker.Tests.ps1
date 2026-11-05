param([string]$Sample)
$ErrorActionPreference='Stop'
$tool=Split-Path $PSScriptRoot -Parent
Add-Type -Path (Join-Path $tool 'wowAuto.CharacterCreate.cs')
$python=Join-Path $tool 'character-create/.runtime/Scripts/python.exe'
if(-not $Sample){throw 'Pass a local reference screenshot; no game capture is performed.'}
$worker=New-Object WowAuto.CharacterCreate.Worker($python,(Join-Path $tool 'character-create/bridge.py'))
try {
    $worker.Send((@{mode='preview';image=$Sample}|ConvertTo-Json -Compress))
    $preview=$false;$finished=$false;$deadline=[datetime]::UtcNow.AddSeconds(45)
    while([datetime]::UtcNow -lt $deadline -and -not $finished){
        $line=$worker.NextLine()
        if($null -ne $line){
            $message=$line|ConvertFrom-Json
            if($message.kind -eq 'operation'){throw 'Offline preview requested game input/capture.'}
            if($message.kind -eq 'error'){throw $message.text}
            if($message.kind -eq 'preview'){
                if(-not $message.hits -or -not $message.png){throw 'OCR preview did not contain text and image.'}
                $preview=$true
            }
            if($message.kind -eq 'finished'){$finished=$true}
        }else{[Threading.Thread]::Sleep(20)}
    }
    if(-not $preview -or -not $finished){throw 'OCR worker protocol did not complete.'}
    'PASS: real private OCR runtime, Unicode JSON pipe and annotated screenshot preview; no window capture or game input.'
}finally{$worker.Dispose()}
