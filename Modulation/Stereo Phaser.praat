# ============================================================
# Praat AudioTools - Stereo_Phaser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Phaser - true variable all-pass phaser. A cascade of
#   first-order all-pass sections is swept by a logarithmic LFO.
#   Dry + wet summation creates the moving notches; feedback around
#   the all-pass cascade adds resonant peaks. Stereo phase offset
#   drives odd/even channels with separate sweep phases.
#
#   This replaces v0.2's variable-delay comb/flanger topology.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.3:
#   - Replaced variable-delay comb with a true all-pass cascade.
#   - Sweep controls are now frequencies in Hz, not delay in ms.
#   - Added selectable 2/4 all-pass stages and true loop feedback.
#   - Log-frequency LFO with local-time phase (start-time invariant).
#   - Removed peak normalization; added attenuation-only Safety_peak.
#   - Dry_wet_percent=0 is an exact bypass.
#   - Mono -> stereo only when active; 3+ channels are preserved with
#     odd channels using the L trajectory and even channels the R one.
#   - Updated visualization to AudioTools house style and plots the
#     analytical all-pass phaser response instead of a fake comb curve.
# ============================================================

form Stereo Phaser v0.4
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Classic 70s Phaser
        option Slow & Deep
        option Jet Plane (High Resonance)
        option Fast Wobble
        option Wide Stereo Widener
        option Sci-Fi Raygun

    comment === LFO / All-pass Sweep ===
    real Rate_Hz 0.5
    positive Sweep_min_Hz 300
    positive Sweep_max_Hz 2200
    optionmenu Stage_configuration: 2
        option 2 stages
        option 4 stages
    comment (Sweep values are all-pass pivot frequencies, not single notch frequencies)

    comment === Stereo Image ===
    real Stereo_phase_offset_deg 180
    comment (180=counter-sweep, 90=quadrature, 0=same trajectory)

    comment === Resonance / Mix ===
    real Feedback_resonance 0.35
    real Dry_wet_percent 50

    comment === Output ===
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
name$ = selected$("Sound")
selectObject: original
duration = Get total duration
sr = Get sampling frequency
channels = Get number of channels
sourceStart = Get start time
sourceEnd = Get end time

# === Apply Presets ===
if preset = 2
    rate_Hz = 0.6
    sweep_min_Hz = 280
    sweep_max_Hz = 1800
    stage_configuration = 2
    stereo_phase_offset_deg = 90
    feedback_resonance = 0.25
    dry_wet_percent = 50
    presetName$ = "Classic70s"
elsif preset = 3
    rate_Hz = 0.20
    sweep_min_Hz = 120
    sweep_max_Hz = 2600
    stage_configuration = 2
    stereo_phase_offset_deg = 180
    feedback_resonance = 0.35
    dry_wet_percent = 55
    presetName$ = "SlowDeep"
elsif preset = 4
    rate_Hz = 0.15
    sweep_min_Hz = 220
    sweep_max_Hz = 3200
    stage_configuration = 2
    stereo_phase_offset_deg = 0
    feedback_resonance = 0.78
    dry_wet_percent = 50
    presetName$ = "JetPlane"
elsif preset = 5
    rate_Hz = 4.0
    sweep_min_Hz = 450
    sweep_max_Hz = 3600
    stage_configuration = 1
    stereo_phase_offset_deg = 180
    feedback_resonance = 0.20
    dry_wet_percent = 45
    presetName$ = "FastWobble"
elsif preset = 6
    rate_Hz = 0.10
    sweep_min_Hz = 650
    sweep_max_Hz = 2200
    stage_configuration = 1
    stereo_phase_offset_deg = 180
    feedback_resonance = 0.0
    dry_wet_percent = 35
    presetName$ = "Widener"
elsif preset = 7
    rate_Hz = 2.5
    sweep_min_Hz = 180
    sweep_max_Hz = 5000
    stage_configuration = 2
    stereo_phase_offset_deg = 180
    feedback_resonance = 0.72
    dry_wet_percent = 50
    presetName$ = "SciFi"
else
    presetName$ = "Custom"
endif

# === Validation / clamps ===
if duration <= 0
    exitScript: "Sound has zero duration."
endif
if rate_Hz < 0
    rate_Hz = 0
endif
if stage_configuration = 1
    stage_count = 2
else
    stage_count = 4
endif
if feedback_resonance < 0
    feedback_resonance = 0
endif
if feedback_resonance > 0.90
    feedback_resonance = 0.90
endif
if dry_wet_percent < 0
    dry_wet_percent = 0
endif
if dry_wet_percent > 100
    dry_wet_percent = 100
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

nyquistSafe = 0.45 * sr
if sweep_min_Hz < 20
    sweep_min_Hz = 20
endif
if sweep_max_Hz > nyquistSafe
    sweep_max_Hz = nyquistSafe
endif
if sweep_min_Hz > nyquistSafe * 0.95
    sweep_min_Hz = max(20, nyquistSafe * 0.25)
endif
if sweep_max_Hz <= sweep_min_Hz
    sweep_max_Hz = min(nyquistSafe, sweep_min_Hz * 1.25)
endif

phase_rad = stereo_phase_offset_deg * pi / 180
wet = dry_wet_percent / 100
dry = 1 - wet

# === Info ===
writeInfoLine: "=== Stereo Phaser v0.4 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", channels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: ""
appendInfoLine: "All-pass stages: ", stage_count
appendInfoLine: "Pivot sweep: ", fixed$(sweep_min_Hz, 1), " - ", fixed$(sweep_max_Hz, 1), " Hz (logarithmic)"
appendInfoLine: "LFO rate: ", fixed$(rate_Hz, 3), " Hz"
appendInfoLine: "Stereo phase: ", fixed$(stereo_phase_offset_deg, 1), " deg"
appendInfoLine: "Feedback resonance: ", fixed$(feedback_resonance, 3)
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: ""

# === Exact bypass ===
if dry_wet_percent = 0
    selectObject: original
    Copy: name$ + "_phaser_" + presetName$
    result = selected("Sound")
    peakBeforeSafety = Get absolute extremum: 0, 0, "None"
    finalPeak = peakBeforeSafety
else
    # Active mono processing becomes stereo. Existing 2+ channel layouts
    # keep their channel count; odd channels use L phase, even channels R.
    if channels = 1
        selectObject: original
        Convert to stereo
        workSource = selected("Sound")
        workChannels = 2
    else
        selectObject: original
        Copy: name$ + "_phaser_source"
        workSource = selected("Sound")
        workChannels = channels
    endif

    # Coefficient control Sound. Three vectorised passes evaluate the LFO,
    # tan() only once, then map the bilinear pivot to all-pass coefficient a.
    selectObject: workSource
    Copy: name$ + "_phaser_coef"
    coefSound = selected("Sound")
    Formula: ~ sweep_min_Hz * exp(ln(sweep_max_Hz/sweep_min_Hz) * (0.5 * (1 + sin(2*pi*rate_Hz*(x-sourceStart) + (((row-1)-2*floor((row-1)/2))*phase_rad)))))
    Formula: ~ tan(pi*self/sr)
    Formula: ~ (self - 1) / (self + 1)

    # The cascade H(z)=((a+z^-1)/(1+a*z^-1))^N is evaluated as one
    # recursive direct-form section. Feedback is a true loop around H:
    # Y = H * (X + feedback*Y), hence (A-feedback*B)Y = B X.
    # With feedback=0 this is a strict all-pass magnitude response.
    src$ = string$(workSource)
    coef$ = string$(coefSound)
    a$ = "object[" + coef$ + ",row,col]"

    numerator$ = ""
    denominatorPast$ = ""
    comb = 1
    for k from 0 to stage_count
        expB = stage_count - k
        expA = k

        if expB = 0
            powB$ = "1"
        elsif expB = 1
            powB$ = "(" + a$ + ")"
        else
            powB$ = "(" + a$ + ")^" + string$(expB)
        endif
        if expA = 0
            powA$ = "1"
        elsif expA = 1
            powA$ = "(" + a$ + ")"
        else
            powA$ = "(" + a$ + ")^" + string$(expA)
        endif

        if k = 0
            xPast$ = "object[" + src$ + ",row,col]"
        else
            xPast$ = "(if col>" + string$(k) + " then object[" + src$ + ",row,col-" + string$(k) + "] else 0 fi)"
        endif

        bTerm$ = "(" + string$(comb) + "*" + powB$ + "*" + xPast$ + ")"
        if numerator$ = ""
            numerator$ = bTerm$
        else
            numerator$ = numerator$ + "+" + bTerm$
        endif

        if k > 0
            yPast$ = "(if col>" + string$(k) + " then self[row,col-" + string$(k) + "] else 0 fi)"
            dTerm$ = "(" + string$(comb) + "*(" + powA$ + "-feedback_resonance*" + powB$ + ")*" + yPast$ + ")"
            if denominatorPast$ = ""
                denominatorPast$ = dTerm$
            else
                denominatorPast$ = denominatorPast$ + "+" + dTerm$
            endif
        endif

        if k < stage_count
            comb = comb * (stage_count - k) / (k + 1)
        endif
    endfor

    if stage_count = 1
        aN$ = "(" + a$ + ")"
    else
        aN$ = "(" + a$ + ")^" + string$(stage_count)
    endif
    d0$ = "(1-feedback_resonance*" + aN$ + ")"
    wetFormula$ = "(" + numerator$ + "-(" + denominatorPast$ + "))/" + d0$

    selectObject: workSource
    Copy: name$ + "_phaser_wet"
    wetPath = selected("Sound")
    Formula: wetFormula$

    # True dry/wet mix from independent source and wet objects.
    work$ = string$(workSource)
    Formula: ~ dry*object[workSource,row,col] + wet*self
    Rename: name$ + "_phaser_" + presetName$
    result = selected("Sound")

    # Safety is attenuation only; never boost a quiet output.
    peakBeforeSafety = Get absolute extremum: 0, 0, "None"
    if safety_peak > 0 and peakBeforeSafety > safety_peak
        Scale peak: safety_peak
    endif
    finalPeak = Get absolute extremum: 0, 0, "None"

    removeObject: coefSound, workSource
endif

appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(finalPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3), " (attenuation only)"
else
    appendInfoLine: "Safety ceiling: off"
endif

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    pageHeight = 6.6
    Erase all

    # Title + metadata
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stereo Phaser v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", name$ + "  |  " + presetName$ + "  |  " + string$(stage_count) + " stages  |  " + fixed$(rate_Hz, 2) + " Hz"

    # Input
    Select outer viewport: 0, 8, 0.72, 1.75
    Select inner viewport: 0.55, 7.72, 0.82, 1.65
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Text left: "yes", "Amp"

    # Output
    Select outer viewport: 0, 8, 1.82, 2.85
    Select inner viewport: 0.55, 7.72, 1.92, 2.75
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # L/R all-pass pivot trajectories
    Select outer viewport: 0, 8, 2.95, 4.10
    Select inner viewport: 0.55, 7.72, 3.06, 4.00
    vizDur = min(3, duration)
    if vizDur <= 0
        vizDur = duration
    endif
    marginF = max(20, 0.08*(sweep_max_Hz-sweep_min_Hz))
    Axes: 0, vizDur, max(0, sweep_min_Hz-marginF), sweep_max_Hz+marginF
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, max(0, sweep_min_Hz-marginF), sweep_max_Hz+marginF
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    nPoints = 300
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        u1 = 0.5*(1+sin(2*pi*rate_Hz*t1))
        u2 = 0.5*(1+sin(2*pi*rate_Hz*t2))
        f1 = sweep_min_Hz*exp(ln(sweep_max_Hz/sweep_min_Hz)*u1)
        f2 = sweep_min_Hz*exp(ln(sweep_max_Hz/sweep_min_Hz)*u2)
        Draw line: t1, f1, t2, f2
    endfor
    Colour: "{0.22, 0.46, 0.82}"
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        u1 = 0.5*(1+sin(2*pi*rate_Hz*t1+phase_rad))
        u2 = 0.5*(1+sin(2*pi*rate_Hz*t2+phase_rad))
        f1 = sweep_min_Hz*exp(ln(sweep_max_Hz/sweep_min_Hz)*u1)
        f2 = sweep_min_Hz*exp(ln(sweep_max_Hz/sweep_min_Hz)*u2)
        Draw line: t1, f1, t2, f2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "All-pass pivot sweep  (purple=L / blue=R)"
    Text left: "yes", "Hz"
    Text bottom: "yes", "Local time (s)"

    # Analytical static response at geometric-mid pivot.
    Select outer viewport: 0, 8, 4.20, 5.55
    Select inner viewport: 0.55, 7.72, 4.31, 5.45
    responseMaxHz = min(10000, 0.45*sr)
    Axes: 0, responseMaxHz, -30, 12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, responseMaxHz, -30, 12
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, responseMaxHz, 0
    pivotMid = sqrt(sweep_min_Hz*sweep_max_Hz)
    gMid = tan(pi*pivotMid/sr)
    aMid = (gMid-1)/(gMid+1)
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    nResp = 320
    for q from 2 to nResp
        f1 = (q-2)/(nResp-1)*responseMaxHz
        f2 = (q-1)/(nResp-1)*responseMaxHz
        if f1 < 0.001
            f1 = 0.001
        endif
        if f2 < 0.001
            f2 = 0.001
        endif
        ph1 = -2*arctan(((1-aMid)/(1+aMid))*tan(pi*f1/sr))*stage_count
        ph2 = -2*arctan(((1-aMid)/(1+aMid))*tan(pi*f2/sr))*stage_count

        den1 = 1 + feedback_resonance^2 - 2*feedback_resonance*cos(ph1)
        den2 = 1 + feedback_resonance^2 - 2*feedback_resonance*cos(ph2)
        wetMag1 = 1/sqrt(max(1e-12, den1))
        wetMag2 = 1/sqrt(max(1e-12, den2))
        denAng1 = arctan2(-feedback_resonance*sin(ph1), 1-feedback_resonance*cos(ph1))
        denAng2 = arctan2(-feedback_resonance*sin(ph2), 1-feedback_resonance*cos(ph2))
        wetPh1 = ph1-denAng1
        wetPh2 = ph2-denAng2
        re1 = dry + wet*wetMag1*cos(wetPh1)
        im1 = wet*wetMag1*sin(wetPh1)
        re2 = dry + wet*wetMag2*cos(wetPh2)
        im2 = wet*wetMag2*sin(wetPh2)
        mag1 = sqrt(re1^2+im1^2)
        mag2 = sqrt(re2^2+im2^2)
        db1 = 20*ln(max(0.0000316,mag1))/ln(10)
        db2 = 20*ln(max(0.0000316,mag2))/ln(10)
        if db1 < -30
            db1 = -30
        endif
        if db2 < -30
            db2 = -30
        endif
        if db1 > 12
            db1 = 12
        endif
        if db2 > 12
            db2 = 12
        endif
        Draw line: f1, db1, f2, db2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Analytical response @ mid pivot " + fixed$(pivotMid,0) + " Hz"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # Summary
    Select outer viewport: 0, 8, 5.68, 6.42
    Select inner viewport: 0.55, 7.72, 5.74, 6.36
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", string$(stage_count) + " stages  |  sweep " + fixed$(sweep_min_Hz,0) + "-" + fixed$(sweep_max_Hz,0) + " Hz  |  rate " + fixed$(rate_Hz,2) + " Hz  |  stereo " + fixed$(stereo_phase_offset_deg,0) + " deg"
    Text: 0.02, "left", 0.18, "half", "Feedback " + fixed$(feedback_resonance,2) + "  |  Wet " + fixed$(dry_wet_percent,0) + "%  |  peak " + fixed$(finalPeak,3) + "  |  " + string$(channels) + "ch input"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
if play_result
    Play
endif
selectObject: result
