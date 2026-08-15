# ============================================================
# Praat AudioTools - Coupled Mesh String.praat
# Author: Shai Cohen
# Version: 1.2.1 compact-form refinement (2026)
#
# COUPLED TWO-MESH + STRING NETWORK
#   - two scalar 8x8 mass-spring meshes
#   - one 12-node string connecting the two meshes
#   - 235 internal springs + two distributed coupling elements
#   - fixed outer mesh boundaries; 84 dynamical nodes
#   - central-difference / Verlet-style time stepping
#
# REFERENCE-RATE PARAMETERIZATION
#   Stiffness and damping values in the form are REFERENCE coefficients at
#   2205 physics steps/s.  When Model_rate_Hz changes:
#
#       k_step = k_ref * (2205 / ModelRate)^2
#       z_step = z_ref * (2205 / ModelRate)
#       F_step = F_ref * (2205 / ModelRate)^2
#
#   This keeps modal tuning and decay approximately invariant when ModelRate
#   is changed for speed/accuracy.  The previous implementation did not scale
#   coefficients, so changing ModelRate transposed and re-damped the model.
#
# v1.2.1 compact-form refinement:
#   - Replaced the tall all-in-one form with a laptop-safe compact launcher.
#   - All detailed physics and geometry parameters remain available through
#     an optional two-page beginPause/endPause advanced wizard.
#   - Advanced pages open AFTER preset application, so they fine-tune the
#     selected preset instead of replacing it with generic defaults.
#   - No physics, DSP, preset, visualization or normalization changes.
#
# v1.2 reviewed:
#   - ModelRate is now a true physics-resolution control rather than a hidden
#     pitch/time-scale control.
#   - Removed integer steps_per_model interpolation. Model-rate output is now
#     converted to Sample_rate_Hz with Praat Resample, so arbitrary rate ratios
#     preserve duration and receive proper interpolation/anti-alias filtering.
#   - Added a conservative explicit stability guard based on the scaled spring
#     coefficients.
#   - Added bounds validation for all normalized geometry parameters.
#   - Added String_pickup_position and Mesh_pickup_mix; the virtual pickup can
#     expose the coupled meshes instead of always reading hard-coded node 70.
#   - Excitation is rate-scaled consistently with the physical time step.
#   - Removed the old 30%-of-duration musical fade-out, which masked the
#     network's natural damping. Only a short optional edge fade remains.
#   - Added optional final normalization and pre-normalization metrics.
#   - Presets renamed to describe network configurations rather than claiming
#     specific instruments such as plate, gong, or prepared piano.
#   - Visualization rebuilt around the mechanism:
#       A actual network geometry / coupling / excitation / pickup
#       B actual mesh1-string-mesh2 structural pickup trajectories
#       C measured output spectrogram at the physically available bandwidth
#       D measured output spectrum
#       model-rate/stability/probe/output QC
# ============================================================

form Coupled Mesh + String v1.2.1 - Compact
    optionmenu Preset 1
        option Custom (baseline values)
        option Tight Symmetric Network
        option Soft Asymmetric Network
        option Strong String-Mesh Coupling
        option Short Damped Network
        option Long Low-Damping Network

    positive Duration_s 2.0
    integer Sample_rate_Hz 44100
    integer Model_rate_Hz 2205

    comment Enable the next option only when you want to edit all model parameters.
    boolean Edit_all_model_parameters 0

    real Edge_fade_s 0.005
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# DETAILED MODEL DEFAULTS
# These are the same values that were previously visible in the single tall
# form. They are exposed unchanged in the optional two-page advanced wizard.
# ---------------------------------------------------------------------------
string_stiffness = 0.49
mesh1_stiffness = 0.24
mesh2_stiffness = 0.24
string_damping = 0.0003
mesh1_damping = 0.0008
mesh2_damping = 0.0003
coupling_stiffness = 0.10
coupling_damping = 0.0001
global_damping = 0.00005

excitation_position = 0.30
excitation_amplitude = 1.0
string_pickup_position = 0.45
mesh_pickup_mix = 0.20
mesh1_attach_x = 0.50
mesh1_attach_y = 0.50
mesh2_attach_x = 0.50
mesh2_attach_y = 0.50

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_label$ = "Custom"

if preset = 2
    preset_label$ = "Tight Symmetric Network"
    duration_s = 2.0
    string_stiffness = 0.49
    mesh1_stiffness = 0.24
    mesh2_stiffness = 0.24
    string_damping = 0.00015
    mesh1_damping = 0.00035
    mesh2_damping = 0.00035
    coupling_stiffness = 0.14
    coupling_damping = 0.00005
    global_damping = 0.00003
    excitation_position = 0.20
    string_pickup_position = 0.16
    mesh_pickup_mix = 0.15
    mesh1_attach_x = 0.40
    mesh1_attach_y = 0.40
    mesh2_attach_x = 0.60
    mesh2_attach_y = 0.60

elsif preset = 3
    preset_label$ = "Soft Asymmetric Network"
    duration_s = 2.5
    string_stiffness = 0.28
    mesh1_stiffness = 0.12
    mesh2_stiffness = 0.07
    string_damping = 0.00045
    mesh1_damping = 0.0012
    mesh2_damping = 0.0018
    coupling_stiffness = 0.07
    coupling_damping = 0.00020
    global_damping = 0.00008
    excitation_position = 0.42
    string_pickup_position = 0.48
    mesh_pickup_mix = 0.45
    mesh1_attach_x = 0.45
    mesh1_attach_y = 0.55
    mesh2_attach_x = 0.62
    mesh2_attach_y = 0.38

elsif preset = 4
    preset_label$ = "Strong String-Mesh Coupling"
    duration_s = 2.5
    string_stiffness = 0.42
    mesh1_stiffness = 0.20
    mesh2_stiffness = 0.18
    string_damping = 0.00030
    mesh1_damping = 0.00070
    mesh2_damping = 0.00090
    coupling_stiffness = 0.28
    coupling_damping = 0.00012
    global_damping = 0.00005
    excitation_position = 0.30
    string_pickup_position = 0.36
    mesh_pickup_mix = 0.55
    mesh1_attach_x = 0.35
    mesh1_attach_y = 0.45
    mesh2_attach_x = 0.65
    mesh2_attach_y = 0.55

elsif preset = 5
    preset_label$ = "Short Damped Network"
    duration_s = 0.9
    string_stiffness = 0.35
    mesh1_stiffness = 0.18
    mesh2_stiffness = 0.16
    string_damping = 0.0040
    mesh1_damping = 0.0050
    mesh2_damping = 0.0060
    coupling_stiffness = 0.10
    coupling_damping = 0.00070
    global_damping = 0.00030
    excitation_position = 0.24
    string_pickup_position = 0.20
    mesh_pickup_mix = 0.30

elsif preset = 6
    preset_label$ = "Long Low-Damping Network"
    duration_s = 4.0
    string_stiffness = 0.47
    mesh1_stiffness = 0.22
    mesh2_stiffness = 0.20
    string_damping = 0.00003
    mesh1_damping = 0.00008
    mesh2_damping = 0.00012
    coupling_stiffness = 0.12
    coupling_damping = 0.00002
    global_damping = 0.00001
    excitation_position = 0.35
    string_pickup_position = 0.48
    mesh_pickup_mix = 0.25
endif

# ---------------------------------------------------------------------------
# OPTIONAL ADVANCED PARAMETER WIZARD
# Main form stays laptop-safe. If requested, all original parameters remain
# editable in two small pages. Preset values have already been applied, so
# these pages act as fine-tuning rather than resetting the selected preset.
# ---------------------------------------------------------------------------
if edit_all_model_parameters

    beginPause: "Coupled Mesh + String - Physics (1/2)"
        comment: "Reference coefficients at 2205 model steps/s"
        positive: "String stiffness", string_stiffness
        positive: "Mesh1 stiffness", mesh1_stiffness
        positive: "Mesh2 stiffness", mesh2_stiffness
        positive: "Coupling stiffness", coupling_stiffness

        positive: "String damping", string_damping
        positive: "Mesh1 damping", mesh1_damping
        positive: "Mesh2 damping", mesh2_damping
        positive: "Coupling damping", coupling_damping
        positive: "Global damping", global_damping
    endPause: "Next", 1

    beginPause: "Coupled Mesh + String - Geometry & Pickup (2/2)"
        comment: "All positions and mixes are normalized; valid range is 0..1"
        real: "Excitation position", excitation_position
        real: "Excitation amplitude", excitation_amplitude
        real: "String pickup position", string_pickup_position
        real: "Mesh pickup mix", mesh_pickup_mix

        real: "Mesh1 attach x", mesh1_attach_x
        real: "Mesh1 attach y", mesh1_attach_y
        real: "Mesh2 attach x", mesh2_attach_x
        real: "Mesh2 attach y", mesh2_attach_y
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if model_rate_Hz < 200
    exitScript: "Model rate must be at least 200 Hz."
endif
if model_rate_Hz > sample_rate_Hz
    exitScript: "Model rate must not exceed the requested audio sample rate."
endif
if duration_s * model_rate_Hz > 500000
    exitScript: "Duration * Model rate exceeds 500,000 physics steps. Reduce duration or Model rate."
endif

if excitation_position < 0 or excitation_position > 1
    exitScript: "Excitation position must be between 0 and 1."
endif
if string_pickup_position < 0 or string_pickup_position > 1
    exitScript: "String pickup position must be between 0 and 1."
endif
if mesh_pickup_mix < 0 or mesh_pickup_mix > 1
    exitScript: "Mesh pickup mix must be between 0 and 1."
endif
if mesh1_attach_x < 0 or mesh1_attach_x > 1 or mesh1_attach_y < 0 or mesh1_attach_y > 1
    exitScript: "Mesh 1 attachment coordinates must be between 0 and 1."
endif
if mesh2_attach_x < 0 or mesh2_attach_x > 1 or mesh2_attach_y < 0 or mesh2_attach_y > 1
    exitScript: "Mesh 2 attachment coordinates must be between 0 and 1."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

# ---------------------------------------------------------------------------
# 2. RATE-INVARIANT STEP COEFFICIENTS
# ---------------------------------------------------------------------------
referenceModelRate = 2205
rateScale = referenceModelRate / model_rate_Hz
stiffnessScale = rateScale * rateScale
dampingScale = rateScale

str_k = string_stiffness * stiffnessScale
m1_k = mesh1_stiffness * stiffnessScale
m2_k = mesh2_stiffness * stiffnessScale
coupling_k = coupling_stiffness * stiffnessScale

str_z = string_damping * dampingScale
m1_z = mesh1_damping * dampingScale
m2_z = mesh2_damping * dampingScale
coupling_z = coupling_damping * dampingScale
global_z0 = global_damping * dampingScale

excitationStepAmplitude = excitation_amplitude * stiffnessScale

# Conservative central-difference stability bound.  For the uncoupled regular
# lattices the graph-Laplacian upper bounds are ~8*k for a 2-D four-neighbour
# mesh and ~4*k for a string. Add coupling headroom at the string endpoints.
stabilityBound = max(8*m1_k, 8*m2_k, 4*str_k + 4*coupling_k)
if stabilityBound >= 3.80
    exitScript: "Scaled stiffness is too close to the explicit-integrator stability limit (bound=",
        ... fixed$(stabilityBound,3), "). Increase Model_rate_Hz or reduce stiffness/coupling."
endif
if max(str_z, m1_z, m2_z, coupling_z, global_z0) >= 1
    exitScript: "Scaled damping coefficient is too large. Increase Model_rate_Hz or reduce damping."
endif

sample_rate = sample_rate_Hz
model_rate = model_rate_Hz
sim_duration = duration_s
nmodel = round(sim_duration * model_rate)
excitationSteps = max(1, round(0.005 * model_rate))

nNodes = 140
nSprings = 235
nDynamicNodes = 84

# ---------------------------------------------------------------------------
# 3. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  COUPLED MESH + STRING v1.2.1"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_label$
appendInfoLine: "Duration: ", fixed$(sim_duration,3), " s"
appendInfoLine: "Audio rate: ", sample_rate, " Hz"
appendInfoLine: "Model rate: ", model_rate, " Hz | reference rate: ", referenceModelRate, " Hz"
appendInfoLine: "Rate scale: ", fixed$(rateScale,4), " | stiffness scale: ", fixed$(stiffnessScale,4)
appendInfoLine: "Stability bound: ", fixed$(stabilityBound,4), " / 4.0 conservative limit"
appendInfoLine: "Pickup: string pos ", fixed$(string_pickup_position,3),
    ... " | mesh mix ", fixed$(mesh_pickup_mix,3)
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 4. STATE / OUTPUT VECTORS
# ---------------------------------------------------------------------------
u# = zero#(nNodes)
u_prev# = zero#(nNodes)

outString# = zero#(nmodel)
outMesh1# = zero#(nmodel)
outMesh2# = zero#(nmodel)
outMix# = zero#(nmodel)

# ---------------------------------------------------------------------------
# 5. STATIC GEOMETRY / INTERPOLATION WEIGHTS
# ---------------------------------------------------------------------------
# Mesh 1 attachment
c1 = floor(mesh1_attach_x * 7) + 1
c2 = min(c1 + 1, 8)
r1 = floor(mesh1_attach_y * 7) + 1
r2 = min(r1 + 1, 8)
wc = mesh1_attach_x * 7 - (c1 - 1)
wr = mesh1_attach_y * 7 - (r1 - 1)
w11 = (1-wc)*(1-wr)
w21 = wc*(1-wr)
w12 = (1-wc)*wr
w22 = wc*wr
i11 = (r1-1)*8 + c1
i21 = (r1-1)*8 + c2
i12 = (r2-1)*8 + c1
i22 = (r2-1)*8 + c2

# Mesh 2 attachment
c1_2 = floor(mesh2_attach_x * 7) + 1
c2_2 = min(c1_2 + 1, 8)
r1_2 = floor(mesh2_attach_y * 7) + 1
r2_2 = min(r1_2 + 1, 8)
wc_2 = mesh2_attach_x * 7 - (c1_2 - 1)
wr_2 = mesh2_attach_y * 7 - (r1_2 - 1)
w11_2 = (1-wc_2)*(1-wr_2)
w21_2 = wc_2*(1-wr_2)
w12_2 = (1-wc_2)*wr_2
w22_2 = wc_2*wr_2
i11_2 = 76 + (r1_2-1)*8 + c1_2
i21_2 = 76 + (r1_2-1)*8 + c2_2
i12_2 = 76 + (r2_2-1)*8 + c1_2
i22_2 = 76 + (r2_2-1)*8 + c2_2

# String excitation interpolation
ek1 = floor(excitation_position * 11) + 1
ek2 = min(ek1 + 1, 12)
ewk = excitation_position * 11 - (ek1 - 1)
eidx1 = 64 + ek1
eidx2 = 64 + ek2

# String pickup interpolation
pk1 = floor(string_pickup_position * 11) + 1
pk2 = min(pk1 + 1, 12)
pwk = string_pickup_position * 11 - (pk1 - 1)
pidx1 = 64 + pk1
pidx2 = 64 + pk2

# ---------------------------------------------------------------------------
# 6. SPRING PAIRS + VECTOR GATHER/SCATTER MATRICES
# ---------------------------------------------------------------------------
sp_i1# = zero#(nSprings)
sp_i2# = zero#(nSprings)
sp_k# = zero#(nSprings)
sp_z# = zero#(nSprings)
sp_idx = 1

# Mesh 1: 56 horizontal + 56 vertical
for r from 1 to 8
    for c from 1 to 7
        sp_i1#[sp_idx] = (r-1)*8 + c
        sp_i2#[sp_idx] = (r-1)*8 + c + 1
        sp_k#[sp_idx] = m1_k
        sp_z#[sp_idx] = m1_z
        sp_idx += 1
    endfor
endfor
for r from 1 to 7
    for c from 1 to 8
        sp_i1#[sp_idx] = (r-1)*8 + c
        sp_i2#[sp_idx] = r*8 + c
        sp_k#[sp_idx] = m1_k
        sp_z#[sp_idx] = m1_z
        sp_idx += 1
    endfor
endfor

# 12-node string: 11 springs
for i from 1 to 11
    sp_i1#[sp_idx] = 64 + i
    sp_i2#[sp_idx] = 65 + i
    sp_k#[sp_idx] = str_k
    sp_z#[sp_idx] = str_z
    sp_idx += 1
endfor

# Mesh 2
for r from 1 to 8
    for c from 1 to 7
        sp_i1#[sp_idx] = 76 + (r-1)*8 + c
        sp_i2#[sp_idx] = 76 + (r-1)*8 + c + 1
        sp_k#[sp_idx] = m2_k
        sp_z#[sp_idx] = m2_z
        sp_idx += 1
    endfor
endfor
for r from 1 to 7
    for c from 1 to 8
        sp_i1#[sp_idx] = 76 + (r-1)*8 + c
        sp_i2#[sp_idx] = 76 + r*8 + c
        sp_k#[sp_idx] = m2_k
        sp_z#[sp_idx] = m2_z
        sp_idx += 1
    endfor
endfor

if sp_idx <> nSprings + 1
    exitScript: "Internal spring-count error."
endif

scatter## = zero##(nNodes, nSprings)
diff## = zero##(nSprings, nNodes)
for s from 1 to nSprings
    scatter##[sp_i1#[s], s] = -1
    scatter##[sp_i2#[s], s] = 1
    diff##[s, sp_i1#[s]] = 1
    diff##[s, sp_i2#[s]] = -1
endfor

# ---------------------------------------------------------------------------
# 7. DYNAMIC-NODE MASK
# ---------------------------------------------------------------------------
mask# = zero#(nNodes)
for r from 2 to 7
    for c from 2 to 7
        mask#[(r-1)*8 + c] = 1
    endfor
endfor
for i from 1 to 12
    mask#[64+i] = 1
endfor
for r from 2 to 7
    for c from 2 to 7
        mask#[76 + (r-1)*8 + c] = 1
    endfor
endfor

# ---------------------------------------------------------------------------
# 8. MAIN PHYSICS LOOP
# ---------------------------------------------------------------------------
appendInfoLine: "Running ", nmodel, " vectorized physics steps..."

one_minus_z0 = 1 - global_z0
maxDisplacement = 0

for m from 1 to nmodel

    # Internal spring forces.
    dist# = mul# (diff##, u#)
    prev_diff# = mul# (diff##, u_prev#)
    vel# = dist# - prev_diff#
    fspr# = sp_k# * dist# + sp_z# * vel#
    frc# = mul# (scatter##, fspr#)

    # Mesh 1 <-> string endpoint coupling.
    pos_m1 = w11*u#[i11] + w21*u#[i21] + w12*u#[i12] + w22*u#[i22]
    prev_m1 = w11*u_prev#[i11] + w21*u_prev#[i21] + w12*u_prev#[i12] + w22*u_prev#[i22]
    vel_m1 = pos_m1 - prev_m1
    pos_s0 = u#[65]
    vel_s0 = u#[65] - u_prev#[65]
    fc1 = coupling_k * (pos_m1 - pos_s0) + coupling_z * (vel_m1 - vel_s0)
    frc#[i11] -= fc1*w11
    frc#[i21] -= fc1*w21
    frc#[i12] -= fc1*w12
    frc#[i22] -= fc1*w22
    frc#[65] += fc1

    # Mesh 2 <-> other string endpoint coupling.
    pos_m2 = w11_2*u#[i11_2] + w21_2*u#[i21_2] + w12_2*u#[i12_2] + w22_2*u#[i22_2]
    prev_m2 = w11_2*u_prev#[i11_2] + w21_2*u_prev#[i21_2] + w12_2*u_prev#[i12_2] + w22_2*u_prev#[i22_2]
    vel_m2 = pos_m2 - prev_m2
    pos_s1 = u#[76]
    vel_s1 = u#[76] - u_prev#[76]
    fc2 = coupling_k * (pos_m2 - pos_s1) + coupling_z * (vel_m2 - vel_s1)
    frc#[i11_2] -= fc2*w11_2
    frc#[i21_2] -= fc2*w21_2
    frc#[i12_2] -= fc2*w12_2
    frc#[i22_2] -= fc2*w22_2
    frc#[76] += fc2

    # Five-millisecond half-sine force pulse, consistently dt^2-scaled.
    if m <= excitationSteps
        ext_f = excitationStepAmplitude * sin(pi*m/excitationSteps)
        frc#[eidx1] += ext_f*(1-ewk)
        frc#[eidx2] += ext_f*ewk
    endif

    # Central-difference / Verlet-style update.
    new_u# = u# + mask# * ((u# - u_prev#)*one_minus_z0 + frc#)
    u_prev# = u#
    u# = new_u#

    # ACTUAL post-update structural probes.
    probeM1 = w11*u#[i11] + w21*u#[i21] + w12*u#[i12] + w22*u#[i22]
    probeM2 = w11_2*u#[i11_2] + w21_2*u#[i21_2] + w12_2*u#[i12_2] + w22_2*u#[i22_2]
    probeString = (1-pwk)*u#[pidx1] + pwk*u#[pidx2]

    outMesh1#[m] = probeM1
    outMesh2#[m] = probeM2
    outString#[m] = probeString
    outMix#[m] = (1-mesh_pickup_mix)*probeString + 0.5*mesh_pickup_mix*(probeM1+probeM2)

    maxDisplacement = max(maxDisplacement, abs(probeString), abs(probeM1), abs(probeM2))
    if maxDisplacement > 1e9
        exitScript: "Simulation diverged. Increase Model_rate_Hz or reduce stiffness/coupling."
    endif
endfor

# ---------------------------------------------------------------------------
# 9. BUILD MODEL-RATE SOUNDS / RESAMPLE
# ---------------------------------------------------------------------------
modelOutput = Create Sound from formula: "cms_model_output", 1, 0, sim_duration, model_rate,
    ... "outMix#[col]"
probeStringSound = Create Sound from formula: "cms_probe_string", 1, 0, sim_duration, model_rate,
    ... "outString#[col]"
probeM1Sound = Create Sound from formula: "cms_probe_mesh1", 1, 0, sim_duration, model_rate,
    ... "outMesh1#[col]"
probeM2Sound = Create Sound from formula: "cms_probe_mesh2", 1, 0, sim_duration, model_rate,
    ... "outMesh2#[col]"

selectObject: probeStringSound
stringProbeRMS = Get root-mean-square: 0, 0
selectObject: probeM1Sound
mesh1ProbeRMS = Get root-mean-square: 0, 0
selectObject: probeM2Sound
mesh2ProbeRMS = Get root-mean-square: 0, 0

if sample_rate <> model_rate
    selectObject: modelOutput
    outputSound = Resample: sample_rate, 50
    removeObject: modelOutput
else
    outputSound = modelOutput
endif

# ---------------------------------------------------------------------------
# 10. SHORT EDGE PROTECTION / OPTIONAL NORMALIZATION
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s, 0.20*sim_duration)
if actualFade > 0
    fadeOutStart = sim_duration - actualFade
    selectObject: outputSound
    Formula: "if x < actualFade then self*(x/actualFade) else if x > fadeOutStart then self*((sim_duration-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_label$, " ", "_", 0)
selectObject: outputSound
Rename: "coupled_mesh_string_" + safePreset$

finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
finalDuration = Get total duration

# ---------------------------------------------------------------------------
# 11. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

removeObject: probeStringSound, probeM1Sound, probeM2Sound

# ---------------------------------------------------------------------------
# 12. PLAY / INFO
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Probe RMS (physical pre-normalization units):"
appendInfoLine: "  Mesh 1: ", fixed$(mesh1ProbeRMS,5),
    ... " | String: ", fixed$(stringProbeRMS,5),
    ... " | Mesh 2: ", fixed$(mesh2ProbeRMS,5)
appendInfoLine: "Pre-normalization: peak ", fixed$(preNormPeak,5),
    ... " | RMS ", fixed$(preNormRMS,5)
appendInfoLine: "Final: peak ", fixed$(finalPeak,5),
    ... " | RMS ", fixed$(finalRMS,5),
    ... " | duration ", fixed$(finalDuration,5), " s"
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .m1c$ = "{0.18,0.43,0.72}"
    .strc$ = "{0.76,0.38,0.18}"
    .m2c$ = "{0.25,0.58,0.38}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20, 7.80, 0.05, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "COUPLED MESH + STRING | " + preset_label$

    Select inner viewport: 0.35, 7.65, 0.37, 0.67
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ... "2 x 8x8 fixed-edge meshes + 12-node string | 235 internal springs + 2 distributed couplings"
    Text: 0.5, "centre", 0.20, "half",
        ... "reference-rate coefficients -> dt-scaled physics -> virtual pickup -> sinc resample -> audio"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL NETWORK GEOMETRY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 0.76, 0.98
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "A  NETWORK GEOMETRY | actual attachment, excitation and pickup positions"

    Select inner viewport: .left, .right, 1.05, 2.28
    Axes: 0, 1, 0, 1
    Paint rectangle: .bg$, 0, 1, 0, 1

    .m1x0 = 0.04
    .m1x1 = 0.31
    .m2x0 = 0.69
    .m2x1 = 0.96
    .my0 = 0.14
    .my1 = 0.86
    .sy = 0.50
    .sx0 = .m1x1
    .sx1 = .m2x0

    # Mesh grids.
    Colour: "{0.67,0.67,0.70}"
    Line width: 0.7
    for .g from 0 to 7
        .gx1 = .m1x0 + (.m1x1-.m1x0)*.g/7
        .gx2 = .m2x0 + (.m2x1-.m2x0)*.g/7
        Draw line: .gx1, .my0, .gx1, .my1
        Draw line: .gx2, .my0, .gx2, .my1

        .gy = .my0 + (.my1-.my0)*.g/7
        Draw line: .m1x0, .gy, .m1x1, .gy
        Draw line: .m2x0, .gy, .m2x1, .gy
    endfor

    # String and 12 nodes.
    Colour: .strc$
    Line width: 1.8
    Draw line: .sx0, .sy, .sx1, .sy
    Line width: 1
    for .n from 0 to 11
        .nx = .sx0 + (.sx1-.sx0)*.n/11
        Paint circle (mm): .strc$, .nx, .sy, 0.65
    endfor

    # Actual mesh attachments and coupling lines.
    .a1x = .m1x0 + (.m1x1-.m1x0)*mesh1_attach_x
    .a1y = .my0 + (.my1-.my0)*mesh1_attach_y
    .a2x = .m2x0 + (.m2x1-.m2x0)*mesh2_attach_x
    .a2y = .my0 + (.my1-.my0)*mesh2_attach_y

    Colour: .m1c$
    Line width: 1.3
    Draw line: .a1x, .a1y, .sx0, .sy
    Paint circle (mm): .m1c$, .a1x, .a1y, 1.1

    Colour: .m2c$
    Draw line: .sx1, .sy, .a2x, .a2y
    Paint circle (mm): .m2c$, .a2x, .a2y, 1.1
    Line width: 1

    # Excitation and virtual string pickup.
    .ex = .sx0 + (.sx1-.sx0)*excitation_position
    .px = .sx0 + (.sx1-.sx0)*string_pickup_position

    Colour: "{0.72,0.15,0.15}"
    Paint circle (mm): "{0.72,0.15,0.15}", .ex, .sy+0.06, 1.1
    Font size: 5
    Text: .ex, "centre", .sy+0.12, "half", "EXCITE"

    Colour: "{0.10,0.10,0.10}"
    Paint circle (mm): "{0.10,0.10,0.10}", .px, .sy-0.06, 1.0
    Text: .px, "centre", .sy-0.13, "half", "PICKUP"

    Colour: "Black"
    Font size: 6
    Text: 0.175, "centre", 0.94, "half", "MESH 1"
    Text: 0.825, "centre", 0.94, "half", "MESH 2"
    Text: 0.50, "centre", 0.92, "half", "STRING"
    Text: 0.50, "centre", 0.06, "half",
        ... "virtual pickup = " + fixed$(1-mesh_pickup_mix,2) + "*string + "
        ... + fixed$(0.5*mesh_pickup_mix,2) + "*(mesh1 + mesh2)"

    Colour: "{0.55,0.55,0.58}"
    Draw rectangle: 0, 1, 0, 1

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL STRUCTURAL PROBES
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 2.43, 2.65
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "B  STRUCTURAL RESPONSE | actual mesh1 / string / mesh2 pickup trajectories"

    selectObject: probeStringSound
    .pStr = Get absolute extremum: 0, 0, "None"
    selectObject: probeM1Sound
    .pM1 = Get absolute extremum: 0, 0, "None"
    selectObject: probeM2Sound
    .pM2 = Get absolute extremum: 0, 0, "None"
    .probeY = 1.05 * max(0.001, .pStr, .pM1, .pM2)

    Select inner viewport: .left, .right, 2.72, 3.69
    Axes: 0, sim_duration, -.probeY, .probeY
    Paint rectangle: .bg$, 0, sim_duration, -.probeY, .probeY
    Colour: .grid$
    Dotted line
    Draw line: 0, 0, sim_duration, 0
    Plain line

    selectObject: probeM1Sound
    Colour: .m1c$
    Draw: 0, 0, -.probeY, .probeY, "no", "Curve"
    selectObject: probeStringSound
    Colour: .strc$
    Draw: 0, 0, -.probeY, .probeY, "no", "Curve"
    selectObject: probeM2Sound
    Colour: .m2c$
    Draw: 0, 0, -.probeY, .probeY, "no", "Curve"

    Axes: 0, sim_duration, -.probeY, .probeY
    Font size: 5
    Colour: .m1c$
    Text: 0.02*sim_duration, "left", 0.88*.probeY, "half", "mesh1"
    Colour: .strc$
    Text: 0.02*sim_duration, "left", 0.68*.probeY, "half", "string"
    Colour: .m2c$
    Text: 0.02*sim_duration, "left", 0.48*.probeY, "half", "mesh2"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Displacement"

    # -----------------------------------------------------------------------
    # PANEL C: MEASURED OUTPUT SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 3.84, 4.06
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "C  MEASURED OUTPUT | spectrogram; bandwidth limited by the physics model rate"

    .specMax = min(0.48*model_rate, 0.45*sample_rate)
    .specStep = max(0.002, sim_duration/1100)

    selectObject: outputSound
    To Spectrogram: 0.03, .specMax, .specStep, 20, "Gaussian"
    .spectrogram = selected("Spectrogram")

    Select inner viewport: .left, .right, 4.13, 5.22
    selectObject: .spectrogram
    Paint: 0, 0, 0, .specMax, 100, 1, 50, 6, 0, 0
    removeObject: .spectrogram

    Axes: 0, sim_duration, 0, .specMax
    Colour: "Black"
    Draw inner box
    Marks left: 4, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT SPECTRUM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35, 7.65, 5.38, 5.60
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half",
        ... "D  MODAL SPECTRUM | measured output up to model Nyquist"

    selectObject: outputSound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Select inner viewport: .left, .right, 5.67, 6.45
    Colour: "{0.52,0.30,0.62}"
    selectObject: .spectrum
    Draw: 0, .specMax, 0, 0, "no"
    removeObject: .spectrum

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50, 7.50, 6.67, 7.80
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93,0.93,0.935}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02, "left", 0.80, "half",
        ... "MODEL  |  " + string$(nDynamicNodes) + " moving nodes  |  "
        ... + string$(nSprings) + " internal springs + 2 couplings  |  fixed mesh edges"

    Text: 0.02, "left", 0.58, "half",
        ... "TIME STEP  |  model " + string$(model_rate) + " Hz"
        ... + "  |  reference " + string$(referenceModelRate) + " Hz"
        ... + "  |  k scale " + fixed$(stiffnessScale,3)
        ... + "  |  stability bound " + fixed$(stabilityBound,3) + "/4"

    Text: 0.02, "left", 0.37, "half",
        ... "PROBES RMS  |  mesh1 " + fixed$(mesh1ProbeRMS,4)
        ... + "  |  string " + fixed$(stringProbeRMS,4)
        ... + "  |  mesh2 " + fixed$(mesh2ProbeRMS,4)

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02, "left", 0.16, "half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0, 1, 0, 1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
