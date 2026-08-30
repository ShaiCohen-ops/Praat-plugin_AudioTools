# ============================================================
# Praat AudioTools - Send_to_Ableton.praat
# Version: 1.0 (2026)
#
# Sends exactly one selected Praat Sound to the existing
# AudioTools Max for Live bridge listening on UDP port 7474.
#
# No Python is required.
# Windows PowerShell is used only to serialize and send the
# Max-compatible OSC-style UDP message:
#
#     import <absolute-wav-path>
#
# The WAV is intentionally NOT deleted here. Ableton Live may
# continue to reference it. Use Clean_Ableton_Bridge.praat only
# after Collect All and Save, or when the bridge files are no
# longer needed.
# ============================================================

if not windows
    exitScript: "Send_to_Ableton v1.0 currently supports Windows only."
endif

if praatVersion >= 7000
    trustRequest = askForTrust()
endif

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object, then run Send_to_Ableton."
endif

soundId = selected("Sound")
soundName$ = selected$("Sound")

# Stable bridge folder. Do not use TEMP: Live clips may keep
# referencing these files until the user collects the project.
rootFolder$ = homeDirectory$ + "/Praat_AudioTools"
bridgeFolder$ = rootFolder$ + "/Ableton_Bridge"
createFolder: rootFolder$
createFolder: bridgeFolder$

# Unique filename: timestamp + random suffix.
d# = date#()
year$   = fixed$(d#[1], 0)
month$  = right$("0" + fixed$(d#[2], 0), 2)
day$    = right$("0" + fixed$(d#[3], 0), 2)
hour$   = right$("0" + fixed$(d#[4], 0), 2)
minute$ = right$("0" + fixed$(d#[5], 0), 2)
second$ = right$("0" + fixed$(d#[6], 0), 2)
rand$   = fixed$(randomInteger(100000, 999999), 0)

fileName$ = "AudioTools_" + year$ + month$ + day$ + "_" + hour$ + minute$ + second$ + "_" + rand$ + ".wav"
wavPath$ = bridgeFolder$ + "/" + fileName$

# Export the selected Praat Sound exactly as it currently exists.
selectObject: soundId
nowarn Save as WAV file: wavPath$

if not fileReadable(wavPath$)
    exitScript: "WAV export failed:" + newline$ + wavPath$
endif

# ------------------------------------------------------------
# Send a Max-compatible OSC-style UDP packet with PowerShell.
# Nothing is installed and no helper file is created.
# The selector is exactly 'import', matching the existing
# AudioTools.LiveBridge.js anything() handler.
# ------------------------------------------------------------
systemRoot$ = environment$("SystemRoot")
if systemRoot$ = ""
    systemRoot$ = "C:/Windows"
endif
powerShell$ = systemRoot$ + "/System32/WindowsPowerShell/v1.0/powershell.exe"

if not fileReadable(powerShell$)
    exitScript: "Windows PowerShell was not found:" + newline$ + powerShell$
endif

# Escape a rare apostrophe in the path for a PowerShell single-quoted string.
psPathArg$ = replace$(wavPath$, "'", "''", 0)

ps$ = "$p='" + psPathArg$ + "';"
ps$ = ps$ + "function P([string]$s){"
ps$ = ps$ + "$b=[System.Text.Encoding]::UTF8.GetBytes($s);"
ps$ = ps$ + "$n=$b.Length+1;"
ps$ = ps$ + "$m=[int]([Math]::Ceiling($n/4.0)*4);"
ps$ = ps$ + "$o=New-Object byte[] $m;"
ps$ = ps$ + "[Array]::Copy($b,0,$o,0,$b.Length);"
ps$ = ps$ + "return ,$o};"
ps$ = ps$ + "$a=P 'import';"
ps$ = ps$ + "$t=P ',s';"
ps$ = ps$ + "$x=P $p;"
ps$ = ps$ + "$q=New-Object byte[] ($a.Length+$t.Length+$x.Length);"
ps$ = ps$ + "[Array]::Copy($a,0,$q,0,$a.Length);"
ps$ = ps$ + "[Array]::Copy($t,0,$q,$a.Length,$t.Length);"
ps$ = ps$ + "[Array]::Copy($x,0,$q,$a.Length+$t.Length,$x.Length);"
ps$ = ps$ + "$u=New-Object System.Net.Sockets.UdpClient;"
ps$ = ps$ + "[void]$u.Send($q,$q.Length,'127.0.0.1',7474);"
ps$ = ps$ + "$u.Close()"

runSubprocess: powerShell$, "-NoProfile", "-Command", ps$

# The WAV is deliberately retained for Ableton Live.
selectObject: soundId

writeInfoLine: "Send request delivered to the Ableton bridge"
appendInfoLine: "  Sound: ", soundName$
appendInfoLine: "  WAV:   ", wavPath$
appendInfoLine: "  UDP:   127.0.0.1:7474"
appendInfoLine: ""
appendInfoLine: "The WAV remains in the AudioTools Ableton bridge folder."
appendInfoLine: "Run Clean_Ableton_Bridge only after Collect All and Save,"
appendInfoLine: "or when these bridge files are no longer needed."
