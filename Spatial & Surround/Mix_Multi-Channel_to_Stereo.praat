# ============================================================
# Praat AudioTools - Mix Multi-Channel to Stereo.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - Added Manual per-channel pan/gain mode
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Mix multichannel sound to stereo with various panning strategies.
#   Supports split L/R, circular panning, and custom configurations.
#
# Usage:
#   Select a multichannel Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - New "Manual" mix mode: per-channel pan + gain from typed lists
#     (space/comma separated, one value per channel; honours the
#     constant-power / linear panning law)
# Changelog v0.2:
#   - Modern selectObject: syntax throughout
#   - Proper object ID tracking
#   - Added mix mode presets (Split, Circular, Mono, Front-Back)
#   - Added visualization of channel panning
#   - Added play_result toggle
#   - Cleanup of intermediate objects
#   - Constant-power panning option
# ============================================================

clearinfo

# ============================================================
# FORM
# ============================================================

form Mix Multi-Channel to Stereo
    comment ─────────────────────────────────────────
    comment Mix Mode
    optionmenu Mix_mode: 2
        option Split L/R (first half left, second half right)
        option Circular Pan (distribute across stereo field)
        option Mono Sum (all channels center)
        option Front-Back (odds left, evens right)
        option Quad to Stereo (1+3 left, 2+4 right)
        option 5.1 Downmix (standard film mix)
        option 7.1 Downmix (standard film mix)
        option Manual (per-channel pan/gain lists)
    comment ─────────────────────────────────────────
    comment Manual mode: one value per channel, space or comma separated
    sentence Manual_pan 0 0.5 1
    comment (0 = hard left, 0.5 = center, 1 = hard right)
    sentence Manual_gain 1 1 1
    comment (linear gain per channel; blank entries default to 1)
    comment ─────────────────────────────────────────
    boolean Use_constant_power_panning 1
    boolean Normalize_output 1
    comment ─────────────────────────────────────────
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
nChan = Get number of channels
duration = Get total duration
sr = Get sampling frequency

if nChan < 2
    exitScript: "Selected Sound has only " + string$(nChan) + " channel(s)." + newline$ + "Need at least 2 channels for stereo mixdown."
endif

# ============================================================
# MIX MODE NAMES
# ============================================================

if mix_mode = 1
    modeName$ = "Split"
elsif mix_mode = 2
    modeName$ = "Circular"
elsif mix_mode = 3
    modeName$ = "Mono"
elsif mix_mode = 4
    modeName$ = "FrontBack"
elsif mix_mode = 5
    modeName$ = "Quad"
elsif mix_mode = 6
    modeName$ = "5.1"
elsif mix_mode = 7
    modeName$ = "7.1"
else
    modeName$ = "Manual"
endif

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Mix Multi-Channel to Stereo v0.4"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Channels: ", nChan
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Mix mode: ", modeName$
appendInfoLine: "Constant power: ", if use_constant_power_panning then "ON" else "OFF" fi
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CALCULATE PANNING COEFFICIENTS
# ============================================================

# Parse a space/comma-separated list into the nth value (1-based), with a
# default if the token is missing or blank. Used by Manual mode.
procedure nthValue: .list$, .n, .default
    # normalise commas to spaces, collapse, then walk tokens
    .s$ = replace$(.list$, ",", " ", 0)
    .count = 0
    .out = .default
    .found = 0
    .rest$ = .s$
    repeat
        .rest$ = replace_regex$(.rest$, "^[ \t]+", "", 1)
        .sp = index(.rest$, " ")
        if .sp > 0
            .tok$ = left$(.rest$, .sp - 1)
            .rest$ = mid$(.rest$, .sp + 1, 100000)
        else
            .tok$ = .rest$
            .rest$ = ""
        endif
        if .tok$ <> ""
            .count = .count + 1
            if .count = .n
                .out = number(.tok$)
                if .out = undefined
                    .out = .default
                endif
                .found = 1
            endif
        endif
    until .rest$ = "" or .found = 1
endproc

# Initialize arrays for L/R gains per channel
for ch from 1 to nChan
    panPos[ch] = 0.5
    gainL[ch] = 0.5
    gainR[ch] = 0.5
endfor

# === SPLIT L/R ===
if mix_mode = 1
    leftCount = floor(nChan / 2)
    rightCount = nChan - leftCount
    
    for ch from 1 to nChan
        if ch <= leftCount
            panPos[ch] = 0
            gainL[ch] = 1 / leftCount
            gainR[ch] = 0
        else
            panPos[ch] = 1
            gainL[ch] = 0
            gainR[ch] = 1 / rightCount
        endif
    endfor
    
    appendInfoLine: "Split: Ch 1-", leftCount, " → Left, Ch ", leftCount + 1, "-", nChan, " → Right"

# === CIRCULAR PAN ===
elsif mix_mode = 2
    for ch from 1 to nChan
        # Distribute channels evenly across stereo field
        # Channel 1 at left, last channel at right
        if nChan > 1
            panPos[ch] = (ch - 1) / (nChan - 1)
        else
            panPos[ch] = 0.5
        endif
        
        if use_constant_power_panning
            # Constant power: L = cos(θ), R = sin(θ) where θ = pan * π/2
            angle = panPos[ch] * pi / 2
            gainL[ch] = cos(angle)
            gainR[ch] = sin(angle)
        else
            # Linear panning
            gainL[ch] = 1 - panPos[ch]
            gainR[ch] = panPos[ch]
        endif
    endfor
    
    appendInfoLine: "Circular: Ch 1 at left → Ch ", nChan, " at right"

# === MONO SUM ===
elsif mix_mode = 3
    for ch from 1 to nChan
        panPos[ch] = 0.5
        gainL[ch] = 1 / nChan
        gainR[ch] = 1 / nChan
    endfor
    
    appendInfoLine: "Mono: All ", nChan, " channels summed to center"

# === FRONT-BACK (odds left, evens right) ===
elsif mix_mode = 4
    oddCount = ceiling(nChan / 2)
    evenCount = floor(nChan / 2)
    
    for ch from 1 to nChan
        if ch mod 2 = 1
            # Odd channels to left
            panPos[ch] = 0
            gainL[ch] = 1 / max(oddCount, 1)
            gainR[ch] = 0
        else
            # Even channels to right
            panPos[ch] = 1
            gainL[ch] = 0
            gainR[ch] = 1 / max(evenCount, 1)
        endif
    endfor
    
    appendInfoLine: "Front-Back: Odd channels left, even channels right"

# === QUAD TO STEREO ===
elsif mix_mode = 5
    if nChan < 4
        appendInfoLine: "Warning: Quad mode expects 4 channels, found ", nChan
    endif
    
    # Standard quad: FL(1), FR(2), RL(3), RR(4)
    # Mix: L = FL + RL*0.7, R = FR + RR*0.7
    for ch from 1 to nChan
        if ch = 1
            panPos[ch] = 0
            gainL[ch] = 1
            gainR[ch] = 0
        elsif ch = 2
            panPos[ch] = 1
            gainL[ch] = 0
            gainR[ch] = 1
        elsif ch = 3
            panPos[ch] = 0.15
            gainL[ch] = 0.7
            gainR[ch] = 0
        elsif ch = 4
            panPos[ch] = 0.85
            gainL[ch] = 0
            gainR[ch] = 0.7
        else
            # Extra channels to center
            panPos[ch] = 0.5
            gainL[ch] = 0.5
            gainR[ch] = 0.5
        endif
    endfor
    
    appendInfoLine: "Quad: FL+RL*0.7 → L, FR+RR*0.7 → R"

# === 5.1 DOWNMIX ===
elsif mix_mode = 6
    if nChan < 6
        appendInfoLine: "Warning: 5.1 mode expects 6 channels, found ", nChan
    endif
    
    # Standard 5.1: L(1), R(2), C(3), LFE(4), Ls(5), Rs(6)
    # ITU downmix: L = L + 0.707*C + 0.707*Ls, R = R + 0.707*C + 0.707*Rs
    sqrt2inv = 1 / sqrt(2)
    
    for ch from 1 to nChan
        if ch = 1
            # Left
            panPos[ch] = 0
            gainL[ch] = 1
            gainR[ch] = 0
        elsif ch = 2
            # Right
            panPos[ch] = 1
            gainL[ch] = 0
            gainR[ch] = 1
        elsif ch = 3
            # Center
            panPos[ch] = 0.5
            gainL[ch] = sqrt2inv
            gainR[ch] = sqrt2inv
        elsif ch = 4
            # LFE - typically reduced or omitted
            panPos[ch] = 0.5
            gainL[ch] = 0.5
            gainR[ch] = 0.5
        elsif ch = 5
            # Left Surround
            panPos[ch] = 0.2
            gainL[ch] = sqrt2inv
            gainR[ch] = 0
        elsif ch = 6
            # Right Surround
            panPos[ch] = 0.8
            gainL[ch] = 0
            gainR[ch] = sqrt2inv
        else
            panPos[ch] = 0.5
            gainL[ch] = 0.3
            gainR[ch] = 0.3
        endif
    endfor
    
    appendInfoLine: "5.1 ITU downmix: L+0.707*C+0.707*Ls → L"

# === 7.1 DOWNMIX ===
elsif mix_mode = 7
    if nChan < 8
        appendInfoLine: "Warning: 7.1 mode expects 8 channels, found ", nChan
    endif
    
    # Standard 7.1: L(1), R(2), C(3), LFE(4), Ls(5), Rs(6), Lb(7), Rb(8)
    sqrt2inv = 1 / sqrt(2)
    
    for ch from 1 to nChan
        if ch = 1
            panPos[ch] = 0
            gainL[ch] = 1
            gainR[ch] = 0
        elsif ch = 2
            panPos[ch] = 1
            gainL[ch] = 0
            gainR[ch] = 1
        elsif ch = 3
            panPos[ch] = 0.5
            gainL[ch] = sqrt2inv
            gainR[ch] = sqrt2inv
        elsif ch = 4
            panPos[ch] = 0.5
            gainL[ch] = 0.5
            gainR[ch] = 0.5
        elsif ch = 5
            panPos[ch] = 0.15
            gainL[ch] = sqrt2inv
            gainR[ch] = 0
        elsif ch = 6
            panPos[ch] = 0.85
            gainL[ch] = 0
            gainR[ch] = sqrt2inv
        elsif ch = 7
            panPos[ch] = 0.1
            gainL[ch] = 0.6
            gainR[ch] = 0
        elsif ch = 8
            panPos[ch] = 0.9
            gainL[ch] = 0
            gainR[ch] = 0.6
        else
            panPos[ch] = 0.5
            gainL[ch] = 0.3
            gainR[ch] = 0.3
        endif
    endfor
    
    appendInfoLine: "7.1 downmix applied"

# === MANUAL (per-channel pan + gain lists) ===
else
    for ch from 1 to nChan
        @nthValue: manual_pan$, ch, 0.5
        .pan = nthValue.out
        @nthValue: manual_gain$, ch, 1
        .gain = nthValue.out
        # clamp
        if .pan < 0
            .pan = 0
        elsif .pan > 1
            .pan = 1
        endif
        if .gain < 0
            .gain = 0
        endif
        panPos[ch] = .pan
        if use_constant_power_panning
            angle = .pan * pi / 2
            gainL[ch] = .gain * cos(angle)
            gainR[ch] = .gain * sin(angle)
        else
            gainL[ch] = .gain * (1 - .pan)
            gainR[ch] = .gain * .pan
        endif
    endfor
    appendInfoLine: "Manual: per-channel pan/gain from form lists"
endif

# ============================================================
# EXTRACT AND MIX CHANNELS
# ============================================================

appendInfoLine: ""
appendInfoLine: "Mixing channels..."

# Create silent stereo output
Create Sound from formula: "left_mix", 1, 0, duration, sr, "0"
leftMix = selected("Sound")

Create Sound from formula: "right_mix", 1, 0, duration, sr, "0"
rightMix = selected("Sound")

# Process each channel
for ch from 1 to nChan
    # Extract this channel
    selectObject: original
    extracted = Extract one channel: ch
    
    # Add to left mix
    if gainL[ch] > 0.001
        gainLStr$ = fixed$(gainL[ch], 10)
        extractedId$ = string$(extracted)
        
        selectObject: leftMix
        Formula: "self + " + gainLStr$ + " * Object_" + extractedId$ + "[col]"
    endif
    
    # Add to right mix
    if gainR[ch] > 0.001
        gainRStr$ = fixed$(gainR[ch], 10)
        extractedId$ = string$(extracted)
        
        selectObject: rightMix
        Formula: "self + " + gainRStr$ + " * Object_" + extractedId$ + "[col]"
    endif
    
    # Log
    appendInfoLine: "  Ch ", ch, ": L=", fixed$(gainL[ch], 3), " R=", fixed$(gainR[ch], 3), " (pan=", fixed$(panPos[ch], 2), ")"
    
    # Clean up extracted channel
    removeObject: extracted
endfor

# ============================================================
# COMBINE TO STEREO
# ============================================================

selectObject: leftMix
plusObject: rightMix
result = Combine to stereo
selectObject: result
Rename: originalName$ + "_stereo_" + modeName$

# Clean up
removeObject: leftMix, rightMix

# ============================================================
# NORMALIZE
# ============================================================

if normalize_output
    selectObject: result
    Scale peak: 0.99
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0.5, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multi-Channel to Stereo: " + originalName$ + " (" + modeName$ + ")" + " | v0.4"
    
    # === Channel Routing Diagram ===
    Select outer viewport: 0, 8, 0.6, 4.5
    Select inner viewport: 0.5, 7.5, 0.8, 4.3
    
    Axes: -0.5, 2.5, -0.5, nChan + 0.5
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", -0.5, 2.5, -0.5, nChan + 0.5
    
    # Draw stereo output (right side)
    # Left speaker
    Paint rectangle: "{0.7, 0.8, 0.9}", 1.8, 2.2, nChan * 0.75, nChan * 0.75 + 0.4
    Font size: 7
    Colour: "Black"
    Text: 2.0, "centre", nChan * 0.75 + 0.2, "half", "L"
    
    # Right speaker
    Paint rectangle: "{0.9, 0.8, 0.7}", 1.8, 2.2, nChan * 0.25, nChan * 0.25 + 0.4
    Text: 2.0, "centre", nChan * 0.25 + 0.2, "half", "R"
    
    # Draw channels and routing
    for ch from 1 to nChan
        yPos = nChan - ch + 0.5
        
        # Channel box
        Paint rectangle: "{0.8, 0.85, 0.9}", -0.3, 0.3, yPos - 0.3, yPos + 0.3
        
        # Channel number
        Font size: 7
        Colour: "Black"
        Text: 0, "centre", yPos, "half", string$(ch)
        
        # Draw routing lines
        Line width: 1 + gainL[ch] * 2
        
        # Line to Left
        if gainL[ch] > 0.01
            # Color based on gain
            r = 0.3
            g = 0.4 + gainL[ch] * 0.4
            b = 0.7
            Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            Draw line: 0.3, yPos, 1.8, nChan * 0.75 + 0.2
        endif
        
        # Line to Right
        Line width: 1 + gainR[ch] * 2
        if gainR[ch] > 0.01
            r = 0.7
            g = 0.4 + gainR[ch] * 0.4
            b = 0.3
            Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
            Draw line: 0.3, yPos, 1.8, nChan * 0.25 + 0.2
        endif
    endfor
    
    # Reset
    Line width: 1
    Colour: "Black"
    
    # === Pan Position Bar ===
    Select outer viewport: 0, 8, 4.6, 5.5
    Select inner viewport: 0.5, 7.5, 4.7, 5.4
    
    Axes: -0.1, 1.1, 0, nChan + 1
    
    # Background and labels
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, nChan + 1
    
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: 0, "centre", nChan + 0.7, "half", "L"
    Text: 0.5, "centre", nChan + 0.7, "half", "C"
    Text: 1, "centre", nChan + 0.7, "half", "R"
    
    # Draw pan positions
    for ch from 1 to nChan
        yPos = nChan - ch + 0.5
        
        # Pan indicator
        panX = panPos[ch]
        
        # Color by position
        r = panX
        b = 1 - panX
        Colour: "{" + fixed$(r, 2) + ", 0.4, " + fixed$(b, 2) + "}"
        Paint circle (mm): "{" + fixed$(r, 2) + ", 0.4, " + fixed$(b, 2) + "}", panX, yPos, 2
        
        # Channel label
        Font size: 6
        Colour: "Black"
        Text: -0.07, "right", yPos, "half", string$(ch)
    endfor
    
    # Border
    Colour: "Black"
    Line width: 1
    Draw line: 0, 0, 0, nChan + 0.5
    Draw line: 0.5, 0, 0.5, nChan + 0.5
    Draw line: 1, 0, 1, nChan + 0.5
    
    # === SUMMARY ===
    Select outer viewport: 0, 8, 5.55, 6.35
    Select inner viewport: 0.60, 7.70, 5.62, 6.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.76, "half", "##Summary##"
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.02, "left", 0.46, "half", string$(nChan) + " channels → stereo | Mode " + modeName$ + " | Power pan " + if use_constant_power_panning then "ON" else "OFF" fi
    Text: 0.02, "left", 0.18, "half", "Duration " + fixed$(duration, 2) + " s | " + string$(round(sr)) + " Hz | Normalize " + if normalize_output then "ON" else "OFF" fi
    Select inner viewport: 0.60, 7.70, 5.62, 6.28
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 0, 6.45
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "MIXDOWN COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Input channels: ", nChan
appendInfoLine: "Output channels: 2 (stereo)"
appendInfoLine: "Mode: ", modeName$

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result
