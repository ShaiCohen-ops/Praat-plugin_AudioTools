# ============================================================
# Praat AudioTools - Lorenz_Deep_Analog.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# LORENZ CONTINUOUS-CONTROL SYNTHESIS
#
# MATHEMATICAL MODEL
# ------------------
#   dx/dt = sigma*(y-x)
#   dy/dt = x*(rho-z)-y
#   dz/dt = x*y-beta*z
#
# The classic Lorenz-63 parameter set is:
#   sigma = 10, rho = 28, beta = 8/3
#
# IMPORTANT SCOPE
# ---------------
# Despite the historical filename "Deep Analog", this script is NOT an analog
# circuit emulation. It numerically integrates a continuous-time nonlinear ODE
# and uses its coordinates as compositional control signals.
#
# The sonification mapping is engine-specific, not part of Lorenz's physical
# convection model:
#   x -> instantaneous oscillator frequency
#   y -> amplitude
#   z -> harmonic brightness
#   z -> equal-power pan in Z-pan stereo mode
#
# In X/Y split stereo, x and y independently drive two phase-continuous
# oscillators, while z controls the shared harmonic brightness.
#
# NUMERICAL INTEGRATION
# ---------------------
# v0.3 used explicit Euler and called the integration step "Chaos speed".
# Since that step was applied once per 500-Hz control sample, changing speed
# also changed numerical accuracy. v0.4 separates these concepts:
#
#   modelStep = Lorenz_time_units_per_second / Control_rate_Hz
#
# The ODE is integrated with fourth-order Runge-Kutta (RK4). Each control
# interval is internally subdivided so that the RK4 substep remains small;
# musical traversal speed can therefore change without deliberately changing
# the integration method.
#
# BURN-IN
# -------
# Chaotic presets integrate the system for a configurable amount of Lorenz
# model time before audio begins. The stable-spiral preset deliberately uses
# zero burn-in so that its approach toward equilibrium remains audible/visible.
#
# PARAMETER REGIME NOTE
# ---------------------
# For rho > 1 the Lorenz system has two non-zero equilibria:
#
#   (+/-sqrt(beta*(rho-1)), +/-sqrt(beta*(rho-1)), rho-1)
#
# When sigma > beta+1, their local stability boundary is:
#
#   rho_H = sigma*(sigma+beta+3)/(sigma-beta-1)
#
# For sigma=10 and beta=8/3, rho_H ~= 24.7368. Thus rho=20 is below
# this boundary and is correctly treated as a settling/spiral regime rather
# than a chaotic "gentle" attractor. Above rho_H the equilibria are unstable,
# but that fact alone does NOT prove that every parameter value is chaotic.
#
# AUDIO MODEL
# -----------
# The continuous control coordinates are resampled to the audio rate. Raw
# coordinates are mapped with smooth tanh normalization based on the Lorenz
# equilibrium scale, rather than min/max-normalizing every realization to the
# same 0..1 range. This preserves more information about parameter changes.
#
# Pitch is mapped logarithmically:
#
#   f_inst = f_base * 2^(0.5*pitchSpanOct*x_norm)
#
# and phase is integrated sample by sample:
#
#   phi[k] = phi[k-1] + 2*pi*f_inst[k]/Fs
#
# Therefore changing Lorenz control changes true instantaneous frequency while
# preserving oscillator phase continuity.
#
# v0.4 changes
# ------------
#   - Euler -> adaptive-substep RK4
#   - "Chaos speed" -> explicit Lorenz time units per audio second
#   - burn-in in Lorenz model time
#   - corrected rho=20 preset to Stable Spiral to Equilibrium
#   - High-rho preset avoids claiming chaos solely from rho
#   - smooth equilibrium-scale coordinate normalization; no realization-wise
#     min/max normalization of the audio controls
#   - true audio-rate phase integration instead of sin(2*pi*f(t)*t)
#   - z remains audible in mono through harmonic brightness
#   - equal-power Z-axis stereo panning
#   - X/Y split uses two genuine independently phase-integrated oscillators
#   - common Nyquist/headroom scaling includes the second harmonic
#   - one common short edge fade
#   - one optional down-only peak protector; no unconditional normalization
#   - visualization rebuilt around actual mechanism and measured output:
#       A measured X-Z trajectory + equilibria
#       B actual normalized x/y/z controls
#       C actual mapped instantaneous frequency
#       D measured spectrogram + model frequency guide
#       integration / dynamics / mapping / output QC
#
# Primary reference:
#   Edward N. Lorenz, "Deterministic Nonperiodic Flow",
#   Journal of the Atmospheric Sciences 20 (1963), 130-141.
# ============================================================

form Lorenz Continuous-Control Synthesis v0.4
    optionmenu Preset 2
        option Custom
        option Classic Chaotic Butterfly
        option Deep Butterfly (slow traversal)
        option Fast Butterfly (rapid traversal)
        option High-Rho Wide Field
        option Stable Spiral to Equilibrium

    positive Duration_s 15.0
    integer Audio_sample_rate_Hz 44100
    positive Base_pitch_Hz 200

    positive Lorenz_time_units_per_second 2.5
    positive Rho 28.0
    positive Sigma 10.0
    positive Beta 2.666666667

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Z-axis pan
        option Stereo X-Y oscillator split

    boolean Edit_integration_mapping_details 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
control_rate_Hz = 500
burn_in_Lorenz_time = 5.0
initial_x = 0.1
initial_y = 0.1
initial_z = 0.1
pitch_span_octaves = 1.40
amplitude_floor = 0.22
maximum_second_harmonic = 0.34
master_amplitude = 0.52
edge_fade_s = 0.035

preset_name$ = "Custom"

# ---------------------------------------------------------------------------
# PRESETS
# ---------------------------------------------------------------------------
if preset = 2
    duration_s = 15.0
    base_pitch_Hz = 200
    lorenz_time_units_per_second = 2.5
    rho = 28.0
    sigma = 10.0
    beta = 2.666666667
    burn_in_Lorenz_time = 5.0
    preset_name$ = "Classic Chaotic Butterfly"

elsif preset = 3
    duration_s = 30.0
    base_pitch_Hz = 60
    lorenz_time_units_per_second = 0.5
    rho = 28.0
    sigma = 10.0
    beta = 2.666666667
    burn_in_Lorenz_time = 5.0
    pitch_span_octaves = 1.15
    preset_name$ = "Deep Butterfly"

elsif preset = 4
    duration_s = 10.0
    base_pitch_Hz = 350
    lorenz_time_units_per_second = 7.5
    rho = 28.0
    sigma = 10.0
    beta = 2.666666667
    burn_in_Lorenz_time = 5.0
    pitch_span_octaves = 1.55
    preset_name$ = "Fast Butterfly"

elsif preset = 5
    duration_s = 20.0
    base_pitch_Hz = 120
    lorenz_time_units_per_second = 2.0
    rho = 90.0
    sigma = 10.0
    beta = 2.666666667
    burn_in_Lorenz_time = 6.0
    pitch_span_octaves = 1.55
    preset_name$ = "High-Rho Wide Field"

elsif preset = 6
    duration_s = 20.0
    base_pitch_Hz = 150
    lorenz_time_units_per_second = 1.0
    rho = 20.0
    sigma = 10.0
    beta = 2.666666667
    burn_in_Lorenz_time = 0.0
    pitch_span_octaves = 1.10
    preset_name$ = "Stable Spiral to Equilibrium"
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PAGE
# ---------------------------------------------------------------------------
if edit_integration_mapping_details
    beginPause: "Lorenz Synthesis - Integration / Mapping Details"
        integer: "Control rate (Hz)", control_rate_Hz
        real: "Burn-in (Lorenz time units)", burn_in_Lorenz_time
        real: "Initial x", initial_x
        real: "Initial y", initial_y
        real: "Initial z", initial_z
        real: "Pitch span (octaves)", pitch_span_octaves
        real: "Amplitude floor (0..1)", amplitude_floor
        real: "Maximum second harmonic (0..1)", maximum_second_harmonic
        real: "Master amplitude", master_amplitude
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if audio_sample_rate_Hz < 8000 or audio_sample_rate_Hz > 192000
    exitScript: "Audio sample rate must be between 8000 and 192000 Hz."
endif
if base_pitch_Hz <= 0
    exitScript: "Base pitch must be greater than zero."
endif
if lorenz_time_units_per_second <= 0 or lorenz_time_units_per_second > 30
    exitScript: "Lorenz time speed must be > 0 and <= 30 model-time units per audio second."
endif
if rho <= 0 or rho > 250
    exitScript: "Rho must be > 0 and <= 250."
endif
if sigma <= 0 or sigma > 100
    exitScript: "Sigma must be > 0 and <= 100."
endif
if beta <= 0 or beta > 50
    exitScript: "Beta must be > 0 and <= 50."
endif
if control_rate_Hz < 100 or control_rate_Hz > 4000
    exitScript: "Control rate must be between 100 and 4000 Hz."
endif
if burn_in_Lorenz_time < 0 or burn_in_Lorenz_time > 100
    exitScript: "Burn-in must be between 0 and 100 Lorenz time units."
endif
if pitch_span_octaves < 0 or pitch_span_octaves > 6
    exitScript: "Pitch span must be between 0 and 6 octaves."
endif
if amplitude_floor < 0 or amplitude_floor > 1
    exitScript: "Amplitude floor must be between 0 and 1."
endif
if maximum_second_harmonic < 0 or maximum_second_harmonic > 1
    exitScript: "Maximum second harmonic must be between 0 and 1."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

if spatial_mode = 1
    spatial_name$ = "Mono"
elsif spatial_mode = 2
    spatial_name$ = "Stereo Z-axis pan"
else
    spatial_name$ = "Stereo X-Y oscillator split"
endif

sr = audio_sample_rate_Hz
controlRate = control_rate_Hz
safeTop = 0.45*sr
twoPi = 2*pi

# ---------------------------------------------------------------------------
# DYNAMICAL REGIME / EQUILIBRIUM SCALES
# ---------------------------------------------------------------------------
hasNonzeroEquilibria = 0
hasHopfBoundary = 0
rhoHopf = 0
eqX = 0
eqZ = 0

if rho > 1
    hasNonzeroEquilibria = 1
    eqX = sqrt(beta*(rho-1))
    eqZ = rho-1
endif

if sigma > beta+1
    hasHopfBoundary = 1
    rhoHopf = sigma*(sigma+beta+3)/(sigma-beta-1)
endif

classicParameters = 0
if abs(sigma-10) < 0.000001 and abs(beta-8/3) < 0.00001 and abs(rho-28) < 0.000001
    classicParameters = 1
endif

if rho < 1
    regime_note$ = "origin equilibrium locally stable"
elsif hasHopfBoundary and rho < rhoHopf
    regime_note$ = "non-zero equilibria locally stable; settling expected"
elsif classicParameters
    regime_note$ = "classic Lorenz-63 chaotic parameter set"
elsif hasHopfBoundary
    regime_note$ = "non-zero equilibria unstable; periodic/chaotic behavior depends on parameters"
else
    regime_note$ = "no simple equilibrium-stability label used for this parameter combination"
endif

# Smooth coordinate normalization scales. These are parameter-derived rather
# than measured min/max scales, so parameter changes remain perceptually visible.
xControlScale = max(1,1.50*max(1,eqX))
yControlScale = xControlScale
zControlCenter = eqZ
zControlScale = max(1,0.75*max(1,abs(eqZ)))

# ---------------------------------------------------------------------------
# NUMERICAL STEP DESIGN
# ---------------------------------------------------------------------------
modelStep = lorenz_time_units_per_second/controlRate
dynamicRate = max(sigma,max(rho,beta))
integrationTargetStep = min(0.004,0.25/dynamicRate)
integrationSubsteps = max(1,ceiling(modelStep/integrationTargetStep))
h = modelStep/integrationSubsteps

if integrationSubsteps > 100
    exitScript: "Requested Lorenz speed/parameters require more than 100 RK4 substeps per control sample. Reduce speed or parameter magnitudes."
endif

totalCtrlSamples = max(2,round(duration_s*controlRate))
burnControlSamples = ceiling(burn_in_Lorenz_time/modelStep)

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LORENZ CONTINUOUS-CONTROL SYNTHESIS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "sigma / rho / beta: ", fixed$(sigma,6), " / ", fixed$(rho,6), " / ", fixed$(beta,9)
appendInfoLine: "Regime note: ", regime_note$
if hasHopfBoundary
    appendInfoLine: "Equilibrium stability boundary rho_H: ", fixed$(rhoHopf,6)
endif
appendInfoLine: "Lorenz model time / audio second: ", fixed$(lorenz_time_units_per_second,4)
appendInfoLine: "Control rate: ", controlRate, " Hz"
appendInfoLine: "Control interval in Lorenz time: ", fixed$(modelStep,8)
appendInfoLine: "RK4 substeps / interval: ", integrationSubsteps
appendInfoLine: "RK4 substep h: ", fixed$(h,9), " Lorenz time units"
appendInfoLine: "Burn-in: ", fixed$(burn_in_Lorenz_time,3), " Lorenz time units"
appendInfoLine: "Spatial mode: ", spatial_name$
appendInfoLine: ""
appendInfoLine: "Integrating Lorenz system with RK4..."

# ---------------------------------------------------------------------------
# RK4 BURN-IN
# ---------------------------------------------------------------------------
lx = initial_x
ly = initial_y
lz = initial_z

if burnControlSamples > 0
    for bi from 1 to burnControlSamples
        for sub from 1 to integrationSubsteps
            k1x = sigma*(ly-lx)
            k1y = lx*(rho-lz)-ly
            k1z = lx*ly-beta*lz

            ax = lx+0.5*h*k1x
            ay = ly+0.5*h*k1y
            az = lz+0.5*h*k1z
            k2x = sigma*(ay-ax)
            k2y = ax*(rho-az)-ay
            k2z = ax*ay-beta*az

            bx = lx+0.5*h*k2x
            by = ly+0.5*h*k2y
            bz = lz+0.5*h*k2z
            k3x = sigma*(by-bx)
            k3y = bx*(rho-bz)-by
            k3z = bx*by-beta*bz

            cx = lx+h*k3x
            cy = ly+h*k3y
            cz = lz+h*k3z
            k4x = sigma*(cy-cx)
            k4y = cx*(rho-cz)-cy
            k4z = cx*cy-beta*cz

            lx = lx+h*(k1x+2*k2x+2*k3x+k4x)/6
            ly = ly+h*(k1y+2*k2y+2*k3y+k4y)/6
            lz = lz+h*(k1z+2*k2z+2*k3z+k4z)/6
        endfor
    endfor
endif

# ---------------------------------------------------------------------------
# CONTROL TRAJECTORY: 3-CHANNEL RAW LORENZ STATE
# ---------------------------------------------------------------------------
controlXYZ = Create Sound from formula:
    ... "lorenz_xyz",3,0,duration_s,controlRate,"0"

selectObject: controlXYZ
totalCtrlSamples = Get number of samples

lobeSwitches = 0
if lx > 0
    previousLobe = 1
elsif lx < 0
    previousLobe = -1
else
    previousLobe = 0
endif

for i from 1 to totalCtrlSamples
    for sub from 1 to integrationSubsteps
        k1x = sigma*(ly-lx)
        k1y = lx*(rho-lz)-ly
        k1z = lx*ly-beta*lz

        ax = lx+0.5*h*k1x
        ay = ly+0.5*h*k1y
        az = lz+0.5*h*k1z
        k2x = sigma*(ay-ax)
        k2y = ax*(rho-az)-ay
        k2z = ax*ay-beta*az

        bx = lx+0.5*h*k2x
        by = ly+0.5*h*k2y
        bz = lz+0.5*h*k2z
        k3x = sigma*(by-bx)
        k3y = bx*(rho-bz)-by
        k3z = bx*by-beta*bz

        cx = lx+h*k3x
        cy = ly+h*k3y
        cz = lz+h*k3z
        k4x = sigma*(cy-cx)
        k4y = cx*(rho-cz)-cy
        k4z = cx*cy-beta*cz

        lx = lx+h*(k1x+2*k2x+2*k3x+k4x)/6
        ly = ly+h*(k1y+2*k2y+2*k3y+k4y)/6
        lz = lz+h*(k1z+2*k2z+2*k3z+k4z)/6
    endfor

    Set value at sample number: 1,i,lx
    Set value at sample number: 2,i,ly
    Set value at sample number: 3,i,lz

    if lx > 0
        thisLobe = 1
    elsif lx < 0
        thisLobe = -1
    else
        thisLobe = previousLobe
    endif

    if previousLobe <> 0 and thisLobe <> previousLobe
        lobeSwitches = lobeSwitches+1
    endif
    previousLobe = thisLobe
endfor

# ---------------------------------------------------------------------------
# EXTRACT RAW CONTROL CHANNELS / MEASURED RANGES
# ---------------------------------------------------------------------------
selectObject: controlXYZ
Extract one channel: 1
rawX = selected("Sound")
Rename: "lorenz_raw_x"
xMin = Get minimum: 0,0,"None"
xMax = Get maximum: 0,0,"None"

selectObject: controlXYZ
Extract one channel: 2
rawY = selected("Sound")
Rename: "lorenz_raw_y"
yMin = Get minimum: 0,0,"None"
yMax = Get maximum: 0,0,"None"

selectObject: controlXYZ
Extract one channel: 3
rawZ = selected("Sound")
Rename: "lorenz_raw_z"
zMin = Get minimum: 0,0,"None"
zMax = Get maximum: 0,0,"None"

appendInfoLine: "Measured x range: ", fixed$(xMin,3), " .. ", fixed$(xMax,3)
appendInfoLine: "Measured y range: ", fixed$(yMin,3), " .. ", fixed$(yMax,3)
appendInfoLine: "Measured z range: ", fixed$(zMin,3), " .. ", fixed$(zMax,3)
appendInfoLine: "X-sign lobe crossings: ", lobeSwitches

# ---------------------------------------------------------------------------
# CONTINUOUS CONTROL -> AUDIO RATE
# ---------------------------------------------------------------------------
selectObject: rawX
xAudio = Resample: sr,50
Rename: "lorenz_x_normalized"
Formula: "tanh(self/" + fixed$(xControlScale,12) + ")"
xAudio = selected("Sound")

selectObject: rawY
yAudio = Resample: sr,50
Rename: "lorenz_y_normalized"
Formula: "tanh(self/" + fixed$(yControlScale,12) + ")"
yAudio = selected("Sound")

selectObject: rawZ
zAudio = Resample: sr,50
Rename: "lorenz_z_normalized"
Formula:
    ... "tanh((self-" + fixed$(zControlCenter,12)
    ... + ")/" + fixed$(zControlScale,12) + ")"
zAudio = selected("Sound")

xAudioId$ = string$(xAudio)
yAudioId$ = string$(yAudio)
zAudioId$ = string$(zAudio)

# ---------------------------------------------------------------------------
# FREQUENCY HEADROOM
# ---------------------------------------------------------------------------
requestedFundTop = base_pitch_Hz*2^(0.5*pitch_span_octaves)
requestedFundBottom = base_pitch_Hz*2^(-0.5*pitch_span_octaves)

if maximum_second_harmonic > 0
    harmonicFactor = 2
else
    harmonicFactor = 1
endif

frequencyScale = min(1,safeTop/(harmonicFactor*requestedFundTop))
effectiveBase = base_pitch_Hz*frequencyScale
actualFundBottom = requestedFundBottom*frequencyScale
actualFundTop = requestedFundTop*frequencyScale
observedXNormMin = tanh(xMin/xControlScale)
observedXNormMax = tanh(xMax/xControlScale)
observedFundBottom = effectiveBase*2^(0.5*pitch_span_octaves*observedXNormMin)
observedFundTop = effectiveBase*2^(0.5*pitch_span_octaves*observedXNormMax)

if actualFundBottom < 20
    exitScript: "Sampling-headroom scaling would move the mapped fundamental below 20 Hz. Reduce pitch span or raise sample rate."
endif

# ---------------------------------------------------------------------------
# X -> INSTANTANEOUS FREQUENCY -> PHASE
# ---------------------------------------------------------------------------
frequencyX = Create Sound from formula:
    ... "lorenz_frequency_x",1,0,duration_s,sr,
    ... fixed$(effectiveBase,12)
    ... + "*2^(0.5*" + fixed$(pitch_span_octaves,12)
    ... + "*object[" + xAudioId$ + ",1,col])"
frequencyXId$ = string$(frequencyX)

phaseX = Create Sound from formula:
    ... "lorenz_phase_x",1,0,duration_s,sr,"0"
selectObject: phaseX
Formula:
    ... "if col=1 then " + fixed$(twoPi/sr,15)
    ... + "*object[" + frequencyXId$ + ",1,col]"
    ... + " else self[col-1]+" + fixed$(twoPi/sr,15)
    ... + "*object[" + frequencyXId$ + ",1,col] fi"
phaseX = selected("Sound")
phaseXId$ = string$(phaseX)

# Y phase is needed only for X/Y split mode.
frequencyY = 0
phaseY = 0
frequencyYId$ = "0"
phaseYId$ = "0"

if spatial_mode = 3
    frequencyY = Create Sound from formula:
        ... "lorenz_frequency_y",1,0,duration_s,sr,
        ... fixed$(effectiveBase,12)
        ... + "*2^(0.5*" + fixed$(pitch_span_octaves,12)
        ... + "*object[" + yAudioId$ + ",1,col])"
    frequencyYId$ = string$(frequencyY)

    phaseY = Create Sound from formula:
        ... "lorenz_phase_y",1,0,duration_s,sr,"0"
    selectObject: phaseY
    Formula:
        ... "if col=1 then " + fixed$(twoPi/sr,15)
        ... + "*object[" + frequencyYId$ + ",1,col]"
        ... + " else self[col-1]+" + fixed$(twoPi/sr,15)
        ... + "*object[" + frequencyYId$ + ",1,col] fi"
    phaseY = selected("Sound")
    phaseYId$ = string$(phaseY)
endif

# ---------------------------------------------------------------------------
# SOUND FORMULA COMPONENTS
# ---------------------------------------------------------------------------
ampY$ = "(" + fixed$(amplitude_floor,9)
    ... + "+" + fixed$(1-amplitude_floor,9)
    ... + "*(0.5+0.5*object[" + yAudioId$ + ",1,col]))"

ampX$ = "(" + fixed$(amplitude_floor,9)
    ... + "+" + fixed$(1-amplitude_floor,9)
    ... + "*(0.5+0.5*object[" + xAudioId$ + ",1,col]))"

harm$ = "(" + fixed$(maximum_second_harmonic,9)
    ... + "*(0.5+0.5*object[" + zAudioId$ + ",1,col]))"

sourceX$ = "(sqrt(2)/sqrt(1+(" + harm$ + ")^2))"
    ... + "*(sin(object[" + phaseXId$ + ",1,col])"
    ... + "+(" + harm$ + ")*sin(2*object[" + phaseXId$ + ",1,col]))"

if spatial_mode = 3
    sourceY$ = "(sqrt(2)/sqrt(1+(" + harm$ + ")^2))"
        ... + "*(sin(object[" + phaseYId$ + ",1,col])"
        ... + "+(" + harm$ + ")*sin(2*object[" + phaseYId$ + ",1,col]))"
endif

# ---------------------------------------------------------------------------
# AUDIO SYNTHESIS
# ---------------------------------------------------------------------------
if spatial_mode = 1
    outputSound = Create Sound from formula:
        ... "Lorenz_" + replace$(preset_name$," ","_",0),
        ... 1,0,duration_s,sr,
        ... fixed$(master_amplitude,9) + "*" + ampY$ + "*" + sourceX$

elsif spatial_mode = 2
    pan$ = "(0.5+0.45*object[" + zAudioId$ + ",1,col])"
    mono$ = "(" + fixed$(master_amplitude,9) + "*" + ampY$ + "*" + sourceX$ + ")"

    outputSound = Create Sound from formula:
        ... "Lorenz_" + replace$(preset_name$," ","_",0),
        ... 2,0,duration_s,sr,
        ... "if row=1 then " + mono$ + "*sqrt(1-" + pan$ + ")"
        ... + " else " + mono$ + "*sqrt(" + pan$ + ") fi"

else
    outputSound = Create Sound from formula:
        ... "Lorenz_" + replace$(preset_name$," ","_",0),
        ... 2,0,duration_s,sr,
        ... "if row=1 then " + fixed$(0.80*master_amplitude,9)
        ... + "*" + ampY$ + "*" + sourceX$
        ... + " else " + fixed$(0.80*master_amplitude,9)
        ... + "*" + ampX$ + "*" + sourceY$ + " fi"
endif

# ---------------------------------------------------------------------------
# COMMON EDGE FADE
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula:
        ... "if x<actualFade then self*(x/actualFade)"
        ... + " else if x>fadeOutStart then self*((duration_s-x)/actualFade)"
        ... + " else self fi fi"
endif

# ---------------------------------------------------------------------------
# FINAL LEVEL
# ---------------------------------------------------------------------------
selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels

appendInfoLine: ""
appendInfoLine: "=== AUDIO MAPPING ==="
appendInfoLine: "Base pitch requested/effective: ", fixed$(base_pitch_Hz,2), " / ", fixed$(effectiveBase,2), " Hz"
appendInfoLine: "Bounded fundamental range: ", fixed$(actualFundBottom,2), " .. ", fixed$(actualFundTop,2), " Hz"
appendInfoLine: "Observed fundamental range: ", fixed$(observedFundBottom,2), " .. ", fixed$(observedFundTop,2), " Hz"
appendInfoLine: "Pitch span: ", fixed$(pitch_span_octaves,3), " octaves"
appendInfoLine: "Frequency headroom scale: ", fixed$(frequencyScale,6)
appendInfoLine: "Mapping: x->pitch, y->amplitude, z->brightness"
if spatial_mode = 2
    appendInfoLine: "Additional mapping: z->equal-power stereo pan"
elsif spatial_mode = 3
    appendInfoLine: "Stereo split: left x-pitch/y-amp; right y-pitch/x-amp"
endif
appendInfoLine: "Pre-protection peak/RMS: ", fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ", fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# CLEANUP CONTROLS
# ---------------------------------------------------------------------------
removeObject: controlXYZ,rawX,rawY,rawZ,xAudio,yAudio,zAudio,frequencyX,phaseX
if spatial_mode = 3
    removeObject: frequencyY,phaseY
endif

# ---------------------------------------------------------------------------
# PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
selectObject: outputSound
if play_result
    Play
endif
selectObject: outputSound


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.90,0.44,0.12}"
    .green$ = "{0.25,0.63,0.32}"
    .red$ = "{0.80,0.20,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "LORENZ CONTINUOUS-CONTROL SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.38,0.70
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.66,"half",
        ... "Lorenz ODE -> RK4 -> smooth x/y/z mapping -> instantaneous frequency -> audio-rate phase integration"
    Text: 0.5,"centre",0.18,"half",
        ... "sigma=" + fixed$(sigma,2) + "  rho=" + fixed$(rho,2)
        ... + "  beta=" + fixed$(beta,4)
        ... + " | " + fixed$(lorenz_time_units_per_second,2)
        ... + " Lorenz-time units/audio s"

    # -----------------------------------------------------------------------
    # PANEL A: X-Z ATTRACTOR / TRAJECTORY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,3.90,0.82,1.02
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "A  ACTUAL X-Z TRAJECTORY | measured integration + equilibrium markers"

    .xPad = max(1,0.08*(xMax-xMin))
    .zPad = max(1,0.08*(zMax-zMin))
    .plotXmin = xMin-.xPad
    .plotXmax = xMax+.xPad
    .plotZmin = max(0,zMin-.zPad)
    .plotZmax = zMax+.zPad

    Select inner viewport: 0.58,3.72,1.08,3.35
    Axes: .plotXmin,.plotXmax,.plotZmin,.plotZmax
    Paint rectangle: .bg$,.plotXmin,.plotXmax,.plotZmin,.plotZmax

    if hasNonzeroEquilibria
        Colour: "{0.55,0.55,0.58}"
        Paint circle (mm): "{0.55,0.55,0.58}",eqX,eqZ,1.2
        Paint circle (mm): "{0.55,0.55,0.58}",-eqX,eqZ,1.2
    else
        Colour: "{0.55,0.55,0.58}"
        Paint circle (mm): "{0.55,0.55,0.58}",0,0,1.2
    endif

    .trajStep = max(1,ceiling(totalCtrlSamples/850))
    .havePrev = 0

    for .i from 1 to totalCtrlSamples
        if ((.i-1) mod .trajStep)=0
            selectObject: rawX
            .xx = Get value at sample number: 1,.i
            selectObject: rawZ
            .zz = Get value at sample number: 1,.i

            if .havePrev
                .timeRatio = .i/totalCtrlSamples
                .rr = 0.18+0.62*.timeRatio
                .gg = 0.46-0.24*.timeRatio
                .bb = 0.80-0.42*.timeRatio
                .col$ = "{" + fixed$(.rr,3) + ","
                    ... + fixed$(.gg,3) + "," + fixed$(.bb,3) + "}"
                Colour: .col$
                Draw line: .prevX,.prevZ,.xx,.zz
            endif

            .prevX = .xx
            .prevZ = .zz
            .havePrev = 1
        endif
    endfor

    Colour: .red$
    Paint circle (mm): .red$,.prevX,.prevZ,1.4

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom: 4,"yes","yes","no"
    Marks left: 4,"yes","yes","no"
    Font size: 5
    Text bottom: "yes","x"
    Text left: "yes","z"

    # -----------------------------------------------------------------------
    # PANEL B: NORMALIZED X/Y/Z CONTROLS
    # -----------------------------------------------------------------------
    Select inner viewport: 4.10,7.65,0.82,1.02
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "B  ACTUAL CONTROL SIGNALS | parameter-scale normalization, not min/max normalization"

    Select inner viewport: 4.30,7.48,1.08,3.35
    Axes: 0,duration_s,-1.08,1.08
    Paint rectangle: .bg$,0,duration_s,-1.08,1.08

    Colour: .grid$
    Dotted line
    Draw line: 0,0,duration_s,0
    Plain line

    .ctrlStep = max(1,ceiling(totalCtrlSamples/700))
    .havePrev = 0

    for .i from 1 to totalCtrlSamples
        if ((.i-1) mod .ctrlStep)=0
            .tt = (.i-1)/controlRate

            selectObject: rawX
            .rx = Get value at sample number: 1,.i
            selectObject: rawY
            .ry = Get value at sample number: 1,.i
            selectObject: rawZ
            .rz = Get value at sample number: 1,.i

            .nx = tanh(.rx/xControlScale)
            .ny = tanh(.ry/yControlScale)
            .nz = tanh((.rz-zControlCenter)/zControlScale)

            if .havePrev
                Colour: .blue$
                Draw line: .prevT,.prevNX,.tt,.nx
                Colour: .orange$
                Draw line: .prevT,.prevNY,.tt,.ny
                Colour: .green$
                Draw line: .prevT,.prevNZ,.tt,.nz
            endif

            .prevT = .tt
            .prevNX = .nx
            .prevNY = .ny
            .prevNZ = .nz
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 5,"yes","yes","no"
    Marks bottom: 4,"yes","yes","no"
    Font size: 5
    Text: 0.03*duration_s,"left",0.93,"half","x"
    Text: 0.13*duration_s,"left",0.93,"half","y"
    Text: 0.23*duration_s,"left",0.93,"half","z"

    # -----------------------------------------------------------------------
    # PANEL C: MAPPED FUNDAMENTAL FREQUENCY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.52,3.73
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "C  X -> INSTANTANEOUS FREQUENCY | phase is integrated at the audio sample rate"

    .fLo = max(20,0.92*observedFundBottom)
    .fHi = 1.08*observedFundTop

    Select inner viewport: 0.82,7.52,3.80,4.78
    Axes: 0,duration_s,.fLo,.fHi
    Paint rectangle: .bg$,0,duration_s,.fLo,.fHi

    Colour: .grid$
    Dotted line
    Draw line: 0,effectiveBase,duration_s,effectiveBase
    Plain line

    .havePrev = 0
    for .i from 1 to totalCtrlSamples
        if ((.i-1) mod .ctrlStep)=0
            .tt = (.i-1)/controlRate
            selectObject: rawX
            .rx = Get value at sample number: 1,.i
            .nx = tanh(.rx/xControlScale)
            .ff = effectiveBase*2^(0.5*pitch_span_octaves*.nx)

            if .havePrev
                Colour: .blue$
                Draw line: .prevFT,.prevF,.tt,.ff
            endif

            .prevFT = .tt
            .prevF = .ff
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "lorenz_display"
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM + MODEL GUIDE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,4.95,5.16
    Axes: 0,1,0,1
    Font size: 7
    Colour: "Black"
    Text: 0.5,"centre",0.5,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + actual mapped fundamental guide"

    .specMax = min(safeTop,max(1200,2.15*actualFundTop))
    .specStep = max(0.002,duration_s/1200)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: 0.82,7.52,5.23,6.42
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Colour: "{0.18,0.54,0.82}"
    Line width: 0.7

    .guideStep = max(1,ceiling(totalCtrlSamples/450))
    .havePrev = 0

    for .i from 1 to totalCtrlSamples
        if ((.i-1) mod .guideStep)=0
            .tt = (.i-1)/controlRate
            selectObject: rawX
            .rx = Get value at sample number: 1,.i
            .nx = tanh(.rx/xControlScale)
            .ff = effectiveBase*2^(0.5*pitch_span_octaves*.nx)

            if .havePrev
                Draw line: .prevGT,.prevGF,.tt,.ff
            endif
            .prevGT = .tt
            .prevGF = .ff
            .havePrev = 1
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.66,7.84
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "DYNAMICS  |  " + regime_note$
        ... + "  |  lobe crossings " + string$(lobeSwitches)

    Text: 0.02,"left",0.58,"half",
        ... "INTEGRATION  |  RK4  |  control " + string$(controlRate)
        ... + " Hz  |  model step " + fixed$(modelStep,6)
        ... + "  |  substeps " + string$(integrationSubsteps)
        ... + "  |  h " + fixed$(h,7)

    Text: 0.02,"left",0.36,"half",
        ... "MAPPING  |  observed fundamental " + fixed$(observedFundBottom,1)
        ... + "-" + fixed$(observedFundTop,1) + " Hz"
        ... + "  |  x pitch / y amp / z brightness"
        ... + "  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  " + spatial_name$
        ... + "  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  RMS " + fixed$(preProtectRMS,4)
        ... + "  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
