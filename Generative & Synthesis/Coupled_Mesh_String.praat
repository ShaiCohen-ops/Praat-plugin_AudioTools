# ============================================================
# Praat AudioTools - CoupledMeshString.praat
# Author: Shai Cohen  (vectorized physical model)
# Version: 1.1
#
# COUPLED MESHES + STRING  (mass-spring network, Verlet integration)
#   - Two 8x8 mass meshes (nodes 1-64 and 77-140)
#   - 12-node string (nodes 65-76) bridging the two meshes
#   - 235 linear springs with per-spring stiffness/damping
#   - Coupling springs attach each mesh to a string endpoint
#
#   Force scatter and state update are expressed as matrix-vector
#   products (mul#) and element-wise vector arithmetic, so the hot
#   loop stays in Praat's compiled kernels rather than the script
#   interpreter. Typical speedup vs. the scalar scatter form: 5-20x.
#
#   ModelRate < SampleRate trades physics resolution for speed.
#   Keep stable:  str_k < 0.5,  mesh_k < 0.25  when downsampling.
# ============================================================

form Coupled Meshes and String (Vectorized)
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use values below)
        option Bright Metallic Plate
        option Dark Gong
        option Prepared Piano
        option Percussive Short
        option Sustained Drone

    comment === Simulation ===
    real Duration 2.0
    positive SampleRate 11025
    positive ModelRate 2205

    comment === Resonator (overridden by preset unless Custom) ===
    positive StrStiffness 0.49
    positive M1Stiffness 0.24
    positive M2Stiffness 0.24
    positive StrDamping 0.0003
    positive M1Damping 0.0008
    positive M2Damping 0.0003
    positive CouplingK 0.1
    positive CouplingZ 0.0001
    positive GlobalZ0 0.00005

    comment === Excitation / Geometry ===
    real ExcitationPosition 0.3
    real ExcitAmplitude 1.0
    real M1AttachX 0.5
    real M1AttachY 0.5
    real M2AttachX 0.5
    real M2AttachY 0.5

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ==========================================
# 0a. APPLY PRESET (overrides resonator block; Custom keeps form values)
# ==========================================
preset_label$ = "Custom"
if preset = 2
    preset_label$ = "Bright Metallic Plate"
    strStiffness = 0.49
    m1Stiffness  = 0.24
    m2Stiffness  = 0.24
    strDamping   = 0.0002
    m1Damping    = 0.0005
    m2Damping    = 0.0005
    couplingK    = 0.12
    couplingZ    = 0.00005
    globalZ0     = 0.00003
elsif preset = 3
    preset_label$ = "Dark Gong"
    strStiffness = 0.42
    m1Stiffness  = 0.24
    m2Stiffness  = 0.20
    strDamping   = 0.0001
    m1Damping    = 0.0004
    m2Damping    = 0.0010
    couplingK    = 0.15
    couplingZ    = 0.0002
    globalZ0     = 0.00008
elsif preset = 4
    preset_label$ = "Prepared Piano"
    strStiffness = 0.49
    m1Stiffness  = 0.22
    m2Stiffness  = 0.18
    strDamping   = 0.0003
    m1Damping    = 0.0008
    m2Damping    = 0.0008
    couplingK    = 0.25
    couplingZ    = 0.00015
    globalZ0     = 0.00005
elsif preset = 5
    preset_label$ = "Percussive Short"
    strStiffness = 0.35
    m1Stiffness  = 0.20
    m2Stiffness  = 0.20
    strDamping   = 0.0025
    m1Damping    = 0.0030
    m2Damping    = 0.0030
    couplingK    = 0.08
    couplingZ    = 0.0005
    globalZ0     = 0.0002
elsif preset = 6
    preset_label$ = "Sustained Drone"
    strStiffness = 0.48
    m1Stiffness  = 0.23
    m2Stiffness  = 0.23
    strDamping   = 0.00005
    m1Damping    = 0.00015
    m2Damping    = 0.00015
    couplingK    = 0.10
    couplingZ    = 0.00003
    globalZ0     = 0.00002
endif

writeInfoLine:  "=== Coupled Meshes + String (Vectorized) ==="
appendInfoLine: "Preset:     ", preset_label$
appendInfoLine: "Duration:   ", duration, " s"
appendInfoLine: "Rates:      SR=", sampleRate, " Hz   Model=", modelRate, " Hz"
appendInfoLine: "Stiffness:  str=", strStiffness, "  m1=", m1Stiffness, "  m2=", m2Stiffness
appendInfoLine: "Damping:    str=", strDamping, "  m1=", m1Damping, "  m2=", m2Damping
appendInfoLine: "Coupling:   k=", couplingK, "  z=", couplingZ, "  globalZ0=", globalZ0
appendInfoLine: ""

# ==========================================
# 0. MAP VARIABLES
# ==========================================
sample_rate  = sampleRate
model_rate   = modelRate
sim_duration = duration

str_k      = strStiffness
m1_k       = m1Stiffness
m2_k       = m2Stiffness
coupling_k = couplingK

str_z      = strDamping
m1_z       = m1Damping
m2_z       = m2Damping
coupling_z = couplingZ
global_z0  = globalZ0

excitation_position = excitationPosition
m1_attach_x = m1AttachX
m1_attach_y = m1AttachY
m2_attach_x = m2AttachX
m2_attach_y = m2AttachY
excit_amplitude = excitAmplitude

nsamps          = round(sim_duration * sample_rate)
nmodel          = round(sim_duration * model_rate)
steps_per_model = round(sample_rate / model_rate)
excit_steps     = round(0.005 * model_rate)

nNodes   = 140
nSprings = 235

u#      = zero#(nNodes)
u_prev# = zero#(nNodes)
out1#   = zero#(nsamps)

# ==========================================
# 1. PRECOMPUTE STATIC INDICES & WEIGHTS
#    (coupling and excitation; cheap scalar ops)
# ==========================================
c1 = floor(m1_attach_x * 7) + 1
c2 = min(c1 + 1, 8)
r1 = floor(m1_attach_y * 7) + 1
r2 = min(r1 + 1, 8)
wc = m1_attach_x * 7 - (c1 - 1)
wr = m1_attach_y * 7 - (r1 - 1)
w11 = (1-wc)*(1-wr)
w21 = wc*(1-wr)
w12 = (1-wc)*wr
w22 = wc*wr
i11 = (r1-1)*8 + c1
i21 = (r1-1)*8 + c2
i12 = (r2-1)*8 + c1
i22 = (r2-1)*8 + c2

c1_2 = floor(m2_attach_x * 7) + 1
c2_2 = min(c1_2 + 1, 8)
r1_2 = floor(m2_attach_y * 7) + 1
r2_2 = min(r1_2 + 1, 8)
wc_2 = m2_attach_x * 7 - (c1_2 - 1)
wr_2 = m2_attach_y * 7 - (r1_2 - 1)
w11_2 = (1-wc_2)*(1-wr_2)
w21_2 = wc_2*(1-wr_2)
w12_2 = (1-wc_2)*wr_2
w22_2 = wc_2*wr_2
i11_2 = 76 + (r1_2-1)*8 + c1_2
i21_2 = 76 + (r1_2-1)*8 + c2_2
i12_2 = 76 + (r2_2-1)*8 + c1_2
i22_2 = 76 + (r2_2-1)*8 + c2_2

ek1   = floor(excitation_position * 11) + 1
ek2   = min(ek1 + 1, 12)
ewk   = excitation_position * 11 - (ek1 - 1)
eidx1 = 64 + ek1
eidx2 = 64 + ek2

# ==========================================
# 2. PRECOMPUTE SPRING PAIRS + SCATTER MATRIX
# ==========================================
sp_i1# = zero#(nSprings)
sp_i2# = zero#(nSprings)
sp_k#  = zero#(nSprings)
sp_z#  = zero#(nSprings)
sp_idx = 1

# Mesh 1 horizontal springs
for r from 1 to 8
    for c from 1 to 7
        sp_i1#[sp_idx] = (r-1)*8 + c
        sp_i2#[sp_idx] = (r-1)*8 + c + 1
        sp_k#[sp_idx]  = m1_k
        sp_z#[sp_idx]  = m1_z
        sp_idx += 1
    endfor
endfor

# Mesh 1 vertical springs
for r from 1 to 7
    for c from 1 to 8
        sp_i1#[sp_idx] = (r-1)*8 + c
        sp_i2#[sp_idx] = r*8 + c
        sp_k#[sp_idx]  = m1_k
        sp_z#[sp_idx]  = m1_z
        sp_idx += 1
    endfor
endfor

# String springs
for i from 1 to 11
    sp_i1#[sp_idx] = 64 + i
    sp_i2#[sp_idx] = 65 + i
    sp_k#[sp_idx]  = str_k
    sp_z#[sp_idx]  = str_z
    sp_idx += 1
endfor

# Mesh 2 horizontal springs
for r from 1 to 8
    for c from 1 to 7
        sp_i1#[sp_idx] = 76 + (r-1)*8 + c
        sp_i2#[sp_idx] = 76 + (r-1)*8 + c + 1
        sp_k#[sp_idx]  = m2_k
        sp_z#[sp_idx]  = m2_z
        sp_idx += 1
    endfor
endfor

# Mesh 2 vertical springs
for r from 1 to 7
    for c from 1 to 8
        sp_i1#[sp_idx] = 76 + (r-1)*8 + c
        sp_i2#[sp_idx] = 76 + r*8 + c
        sp_k#[sp_idx]  = m2_k
        sp_z#[sp_idx]  = m2_z
        sp_idx += 1
    endfor
endfor

# Two incidence matrices, built together in one pass:
#
#   scatter##[n, s] = -1 if spring s has i1 = n   (force pulls n toward i2)
#   scatter##[n, s] = +1 if spring s has i2 = n
#   -> frc# = mul# (scatter##, fspr#) scatters per-spring forces onto nodes.
#
#   diff##[s, n] = +1 if spring s has i1 = n
#   diff##[s, n] = -1 if spring s has i2 = n
#   -> mul# (diff##, u#) gathers  u[i1] - u[i2]  for every spring at once.
#
# Praat scripting does not allow vector-valued indexing (u#[sp_i1#]), so we
# express the gather as a matrix-vector product too.
scatter## = zero##(nNodes, nSprings)
diff##    = zero##(nSprings, nNodes)
for s from 1 to nSprings
    scatter##[sp_i1#[s], s] = -1
    scatter##[sp_i2#[s], s] =  1
    diff##[s, sp_i1#[s]]    =  1
    diff##[s, sp_i2#[s]]    = -1
endfor

# ==========================================
# 3. PRECOMPUTE INTERIOR MASK FOR VERLET
# ==========================================
# Boundary nodes stay at zero (fixed edges). Build a 0/1 mask so the
# Verlet step can be a single masked vector expression.
mask# = zero#(nNodes)
for r from 2 to 7
    for c from 2 to 7
        mask#[(r-1)*8 + c] = 1
    endfor
endfor
for i from 1 to 12
    mask#[64 + i] = 1
endfor
for r from 2 to 7
    for c from 2 to 7
        mask#[76 + (r-1)*8 + c] = 1
    endfor
endfor

# ==========================================
# 4. MAIN SIMULATION LOOP
# ==========================================
appendInfoLine: "Running simulation (", nmodel, " physics steps)..."

prev_probe   = 0
curr_probe   = 0
audio_idx    = 1
one_minus_z0 = 1 - global_z0
inv_spm      = 1 / steps_per_model

for m from 1 to nmodel

    # --- SPRING FORCES: fully vectorized (three mul# calls, no scripted inner loop) ---
    # diff## gathers  u[i1]-u[i2]  for all 235 springs in one matrix-vector product.
    # scatter## sends per-spring forces back to the 140 nodes with correct signs.
    dist#      = mul# (diff##, u#)
    prev_diff# = mul# (diff##, u_prev#)
    vel#       = dist# - prev_diff#
    fspr#      = sp_k# * dist# + sp_z# * vel#
    frc#       = mul# (scatter##, fspr#)

    # --- COUPLING PROXIES (small scalar block, kept as-is) ---
    pos_m1  = w11*u#[i11]      + w21*u#[i21]      + w12*u#[i12]      + w22*u#[i22]
    prev_m1 = w11*u_prev#[i11] + w21*u_prev#[i21] + w12*u_prev#[i12] + w22*u_prev#[i22]
    vel_m1  = pos_m1 - prev_m1
    pos_s0  = u#[65]
    vel_s0  = u#[65] - u_prev#[65]
    fc1     = coupling_k * (pos_m1 - pos_s0) + coupling_z * (vel_m1 - vel_s0)
    frc#[i11] -= fc1 * w11
    frc#[i21] -= fc1 * w21
    frc#[i12] -= fc1 * w12
    frc#[i22] -= fc1 * w22
    frc#[65]  += fc1

    pos_m2  = w11_2*u#[i11_2]      + w21_2*u#[i21_2]      + w12_2*u#[i12_2]      + w22_2*u#[i22_2]
    prev_m2 = w11_2*u_prev#[i11_2] + w21_2*u_prev#[i21_2] + w12_2*u_prev#[i12_2] + w22_2*u_prev#[i22_2]
    vel_m2  = pos_m2 - prev_m2
    pos_s1  = u#[76]
    vel_s1  = u#[76] - u_prev#[76]
    fc2     = coupling_k * (pos_m2 - pos_s1) + coupling_z * (vel_m2 - vel_s1)
    frc#[i11_2] -= fc2 * w11_2
    frc#[i21_2] -= fc2 * w21_2
    frc#[i12_2] -= fc2 * w12_2
    frc#[i22_2] -= fc2 * w22_2
    frc#[76]    += fc2

    # --- EXCITATION ---
    if m <= excit_steps
        ext_f = excit_amplitude * sin(pi * m / excit_steps)
        frc#[eidx1] += ext_f * (1 - ewk)
        frc#[eidx2] += ext_f * ewk
    endif

    # --- VERLET UPDATE: single masked vector expression ---
    # Rewrite  new_u = 2*u - u_prev + frc - (u - u_prev)*z0
    #         = u + (u - u_prev)*(1 - z0) + frc
    # Boundary nodes: mask = 0, so they keep u = 0 forever.
    # Since boundary u is always 0, copying u -> u_prev preserves u_prev = 0 too.
    new_u#  = u# + mask# * ((u# - u_prev#) * one_minus_z0 + frc#)
    u_prev# = u#
    u#      = new_u#

    # --- AUDIO OUTPUT with linear interpolation ---
    prev_probe  = curr_probe
    curr_probe  = u#[70]
    delta_probe = curr_probe - prev_probe
    for s from 1 to steps_per_model
        if audio_idx <= nsamps
            out1#[audio_idx] = prev_probe + (s * inv_spm) * delta_probe
            audio_idx += 1
        endif
    endfor

endfor

# ==========================================
# 5. BUILD SOUND, SHAPE ENDS, NORMALIZE
# ==========================================
Create Sound from formula: "Modeled_Instrument", 1, 0, sim_duration, sample_rate, "out1# [col]"
sound = selected("Sound")

# Click-prevention fade-in: 5 ms linear ramp.
# Excitation is already a half-sine pulse so amplitude starts at zero,
# but a short linear fade defends against any sample-rate interpolation
# transient at t=0.
Formula: "self * if x < 0.005 then x/0.005 else 1 fi"

# Musical fade-out: half-cosine (equal-power-ish) over adaptive length.
# Length = 30% of duration, capped at 400 ms. Cosine is C1-smooth at both
# endpoints - no slope discontinuity where the fade begins, no abrupt
# cutoff where it ends (unlike the linear fade in v1.0).
fade_len   = min(0.4, sim_duration * 0.3)
fade_begin = sim_duration - fade_len

fadeOut$ = "if x > " + fixed$(fade_begin, 6)
fadeOut$ = fadeOut$ + " then self * 0.5 * (1 + cos(pi * (x - " + fixed$(fade_begin, 6) + ") / " + fixed$(fade_len, 6) + "))"
fadeOut$ = fadeOut$ + " else self fi"
Formula: fadeOut$

Scale peak: 0.99

# ==========================================
# 6. VISUALIZATION
# ==========================================
if draw_visualization
    @drawVisualization
endif

# ==========================================
# 7. PLAY
# ==========================================
if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")


# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    Erase all

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.95
    Select inner viewport: 0, 8, 0, 0.95
    Axes: 0, 1, 0, 1

    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.78, "half",
    ... "##Coupled Meshes + String##  -  " + preset_label$

    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.32, "half",
    ... "Dur=" + fixed$(sim_duration, 2) + " s  | SR=" + fixed$(sample_rate, 0)
    ...     + " Hz  | Model=" + fixed$(model_rate, 0) + " Hz"
    ...     + "  | Nodes=140  | Springs=235"

    # === Waveform ===
    Select outer viewport: 0, 8, 1.0, 2.8
    Select inner viewport: 0.6, 7.7, 1.1, 2.7

    selectObject: sound
    Colour: "{0.2, 0.4, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "##Amplitude##"
    Text bottom: "yes", "Time (s)"

    Font size: 8
    Text top: "no", "##Waveform##"

    # === Spectrum ===
    Select outer viewport: 0, 8, 3.0, 4.8
    Select inner viewport: 0.6, 7.7, 3.1, 4.7

    selectObject: sound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Colour: "{0.6, 0.3, 0.5}"
    Draw: 0, 5000, 0, 0, "no"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 1000, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "##Power (dB)##"
    Text bottom: "yes", "Frequency (Hz)"

    Font size: 8
    Text top: "no", "##Magnitude Spectrum (0 - 5000 Hz)##"

    removeObject: .spectrum

    # === Spectrogram ===
    Select outer viewport: 0, 8, 5.0, 7.0
    Select inner viewport: 0.6, 7.7, 5.1, 6.9

    selectObject: sound
    .maxFreq = 5000
    To Spectrogram: 0.03, .maxFreq, 0.005, 20, "Gaussian"
    .spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"

    removeObject: .spectrogram

    Select inner viewport: 0.6, 7.7, 5.1, 6.9
    Axes: 0, .totalDur, 0, .maxFreq

    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "##Freq (Hz)##"
    Text bottom: "yes", "Time (s)"

    Colour: "Black"
    Font size: 8
    Text top: "no", "##Spectrogram##"

    # === Summary panel (grey background, library standard) ===
    Select outer viewport: 0, 8, 7.1, 7.95
    Select inner viewport: 0.6, 7.7, 7.15, 7.9
    Axes: 0, 1, 0, 1

    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half",
    ... "##Preset:## " + preset_label$
    Text: 0.02, "left", 0.58, "half",
    ... "##Stiffness:##  str=" + fixed$(str_k, 3) + "  m1=" + fixed$(m1_k, 3) + "  m2=" + fixed$(m2_k, 3)
    ...     + "    ##Damping:##  str=" + fixed$(str_z, 5) + "  m1=" + fixed$(m1_z, 5) + "  m2=" + fixed$(m2_z, 5)
    Text: 0.02, "left", 0.34, "half",
    ... "##Coupling:##  k=" + fixed$(coupling_k, 3) + "  z=" + fixed$(coupling_z, 5)
    ...     + "    ##GlobalZ0:## " + fixed$(global_z0, 6)
    ...     + "    ##Excit:##  pos=" + fixed$(excitation_position, 2) + "  amp=" + fixed$(excit_amplitude, 2)
    Text: 0.02, "left", 0.10, "half",
    ... "##Fade-out:## cosine, " + fixed$(fade_len * 1000, 0) + " ms"
    ...     + "    ##M1 attach:## (" + fixed$(m1_attach_x, 2) + ", " + fixed$(m1_attach_y, 2) + ")"
    ...     + "    ##M2 attach:## (" + fixed$(m2_attach_x, 2) + ", " + fixed$(m2_attach_y, 2) + ")"

    Font size: 10
    Colour: "Black"
    Line width: 1

endproc
