# ============================================================
# Praat AudioTools - Advanced_Stereo_Panner.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2.1 (2026)
# v2.2 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Psychoacoustic stereo panner with a drawable pan trajectory.
#   Cues: interaural level difference, interaural time difference,
#   far-ear head-shadow filtering, and distance attenuation with air
#   absorption.
#
#   NOT an HRTF-based binaural renderer. On loudspeakers each ear hears
#   both channels, so there is acoustic crosstalk and the two channels
#   are not the two ear signals. On headphones the ILD and ITD act more
#   directly, but there is still no HRTF and no pinna filtering, so no
#   elevation cue and no front/back discrimination. Treat it as a
#   creative stereo tool, not a binaural simulation.
#
# Changelog v2.0 (2026):
#   - FIX (most important): the final Scale peak erased the distance
#     effect. Distance multiplied both channels by the same factor and
#     Scale peak then rescaled the whole object back up to 0.95, so a
#     source at 30 m came out at exactly the same level as one at 1 m.
#     Only the filtering survived. Replaced with a peak CEILING that
#     attenuates but never boosts: if the peak exceeds the ceiling both
#     channels are scaled down by one shared factor, otherwise nothing
#     happens. Distance, pan level and the L/R ratio all survive.
#   - FIX: ILD was counted twice and ILD_max_dB bounded nothing. The
#     script applied equal-power panning, which already produces a
#     level difference, and then multiplied one side by 10^(A/20) and
#     the other by 10^(-A/20), adding 2A more. At pan 0.5 with
#     ILD_max 12 the equal-power law alone gives 4.77 dB, the boost
#     adds 12, and the total is 16.77 dB - while the report said
#     "±6 dB", which is neither figure. At hard pan the equal-power law
#     already sends the far ear to exactly zero, so the ILD is infinite
#     and ILD_max_dB has no effect at all; worse, the far channel is
#     silent, so its ITD and head shadow are inaudible.
#     There is now a Panning_model choice:
#       Conventional equal-power - sqrt law only, no separate ILD.
#       Bounded psychoacoustic ILD - solve the gains FROM the wanted
#         difference: D = pan * ILD_max, r = 10^(D/20),
#         gL = 1/sqrt(1+r^2), gR = r/sqrt(1+r^2). Then gL^2+gR^2 = 1
#         exactly and the ILD is exactly D. At hard pan with ILD_max 12
#         the far ear sits at 0.2436 rather than 0, so the ITD and the
#         head shadow stay audible, which is the point of having them.
#   - FIX: the distance comment claimed an inverse-square law but the
#     formula was 1/(1 + 2d/dmax), a softened normalised rolloff. It
#     also attenuated the 1 m reference to 0.9375, and spanned only
#     9.0 dB from 1 m to 30 m where inverse-distance spans 29.5 dB.
#     Distance_model now offers a true inverse-distance amplitude law
#     (d0/max(d,d0), pressure ~ 1/d, energy ~ 1/d^2) or the v1.1 curve
#     kept under its real name, Softened rolloff.
#   - FIX: ITD truncated the delayed ear. The delay was made by
#     concatenating silence and then extracting 0 to duration, which
#     cut the last ITD milliseconds off that channel. The output is now
#     allowed to run to duration + max ITD and the undelayed channel is
#     padded, so nothing is lost.
#   - FIX: air absorption switched on as a step. It was gated on
#     distance > 1, so 1.000 m was unfiltered and 1.001 m jumped
#     straight to a 10908 Hz lowpass. It is now continuous in
#     q = (d - d0) / (dmax - d0), clamped to 0..1, so there is no
#     filtering at the reference distance and it deepens smoothly.
#   - FIX: no Nyquist check on either cutoff. At 8 or 16 kHz the 8000
#     Hz head-shadow default and the 12000 Hz air default are at or
#     above Nyquist. Both are now clamped to 0.95 * fs/2.
#   - FIX: no check that Distance <= Max_distance, which also let the
#     visualization bar overrun its frame.
#   - RENAME: "Spectral cues" is a far-ear head-shadow lowpass. It does
#     not model pinna notches, elevation or front/back cues, so it is
#     named for what it does.
#   - FIX: the report and the plot printed the gains from before Scale
#     peak, which were not the gains in the delivered file. They now
#     report the actual gains, the actual ILD in dB, the safety
#     attenuation if any, the ITD in both samples and milliseconds, the
#     distance attenuation in dB, and the output duration.
#   - v2.2 FIX: the drawing tool used beginPause to wait while you drew,
#     which fails with "Praat cannot have more than one pause form at a
#     time" - the script's own form window is already a pause form, and
#     Praat allows only one. Replaced with a two-pass handshake: run
#     once with just the Sound selected to create and open the
#     trajectory, draw at your own pace with no script waiting on you,
#     then select the Sound AND the PanTrajectory and run again. This
#     is better than a pause anyway: the editor can be closed and
#     reopened, and pass 2 can be re-run any number of times against
#     the same drawn curve with different ITD, shadow or distance
#     settings. A drawn tier is never deleted by the script.
#   - NEW: DRAWABLE PAN TRAJECTORY. Pan can now be a curve over time
#     instead of one number. Pan_mode offers a static value, six
#     built-in trajectory shapes, or Draw your own - which opens a
#     RealTier editor, waits while you draw the path, and reads it back.
#     Along the trajectory the script computes, per control point:
#       - the panning gains, from whichever model is selected;
#       - a time-varying fractional ITD, applied by reading the source
#         at x - delay(x) with Praat's own interpolation, so the delay
#         is continuous rather than quantised to whole samples;
#       - a time-varying head-shadow depth, as a continuous crossfade
#         between the dry channel and a lowpassed copy.
#     The gains ride an AmplitudeTier, so they interpolate at audio
#     rate with no stepping.
#   - NOTE on the two shadow implementations: static mode moves the
#     filter cutoff, as v1.1 did, so its sound is unchanged. Trajectory
#     mode crossfades between dry and one fixed-cutoff lowpass, since a
#     cutoff cannot be swept inside a single Praat filter call. Both
#     are reported.
#
# Changelog v1.1:
#   - Added input validation, visualization, play toggle.
# ============================================================

# === Check Input (before the form) ===
# A RealTier may be selected alongside the Sound: that is how a drawn
# pan trajectory is handed back to the script on the second pass.
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
        ... + " (A PanTrajectory RealTier may be selected with it.)"
endif
nTiersSelected = numberOfSelected("RealTier")
if nTiersSelected > 1
    exitScript: "Please select at most one RealTier."
endif
soundIn = selected("Sound")
tierIn = 0
if nTiersSelected = 1
    tierIn = selected("RealTier")
endif

form Advanced Stereo Panner
    comment === PAN MODE ===
    optionmenu Pan_mode: 1
        option: "Static position"
        option: "Trajectory: left to right"
        option: "Trajectory: right to left"
        option: "Trajectory: sine sweep"
        option: "Trajectory: centre out to both sides"
        option: "Trajectory: sides in to centre"
        option: "Trajectory: pendulum (damped sine)"
        option: "Trajectory: DRAW YOUR OWN (two passes - see Info)"

    comment === Static presets (used only when Pan mode = Static) ===
    optionmenu Preset: 1
        option: "Centre"
        option: "Hard Left"
        option: "Hard Right"
        option: "Medium Left"
        option: "Medium Right"
        option: "Subtle Left"
        option: "Subtle Right"
        option: "Wide Left"
        option: "Wide Right"
        option: "Custom (use value below)"
    real Pan_position 0.0

    comment === Trajectory settings (cycles applies to oscillating shapes) ===
    positive Trajectory_cycles 2.0
    real Trajectory_depth 1.0

    comment === PANNING MODEL ===
    optionmenu Panning_model: 2
        option: "Conventional equal-power (sqrt law, no separate ILD)"
        option: "Bounded psychoacoustic ILD (exactly ILD_max at hard pan)"
    positive ILD_max_dB 12

    comment === ITD (Interaural Time Difference) ===
    boolean Use_ITD 1
    positive Max_ITD_ms 0.65

    comment === Far-ear head shadow (lowpass on the far channel) ===
    boolean Use_head_shadow 1
    positive Head_shadow_cutoff_Hz 8000
    real Shadow_depth 0.5

    comment === Distance ===
    boolean Use_distance 1
    optionmenu Distance_model: 1
        option: "Inverse distance (pressure ~ 1/d)"
        option: "Softened rolloff (the v1.1 curve)"
    positive Distance_meters 1.0
    positive Max_distance_meters 30.0
    positive Reference_distance_meters 1.0
    boolean Use_air_absorption 1
    positive Air_cutoff_at_reference_Hz 12000

    comment === Output ===
    real Peak_ceiling 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Static presets ===
if pan_mode = 1
    if preset = 1
        pan_position = 0.0
        presetName$ = "Centre"
    elsif preset = 2
        pan_position = -1.0
        presetName$ = "HardLeft"
    elsif preset = 3
        pan_position = 1.0
        presetName$ = "HardRight"
    elsif preset = 4
        pan_position = -0.5
        presetName$ = "MediumLeft"
    elsif preset = 5
        pan_position = 0.5
        presetName$ = "MediumRight"
    elsif preset = 6
        pan_position = -0.25
        presetName$ = "SubtleLeft"
    elsif preset = 7
        pan_position = 0.25
        presetName$ = "SubtleRight"
    elsif preset = 8
        pan_position = -0.75
        presetName$ = "WideLeft"
    elsif preset = 9
        pan_position = 0.75
        presetName$ = "WideRight"
    else
        presetName$ = "Custom"
    endif
elsif pan_mode = 2
    presetName$ = "L2R"
elsif pan_mode = 3
    presetName$ = "R2L"
elsif pan_mode = 4
    presetName$ = "SineSweep"
elsif pan_mode = 5
    presetName$ = "CentreOut"
elsif pan_mode = 6
    presetName$ = "SidesIn"
elsif pan_mode = 7
    presetName$ = "Pendulum"
else
    presetName$ = "Drawn"
endif

isTrajectory = 0
if pan_mode > 1
    isTrajectory = 1
endif

# === Guards ===
if pan_position < -1 or pan_position > 1
    exitScript: "Pan position must be between -1 and 1."
endif
if trajectory_depth < 0
    trajectory_depth = 0
endif
if trajectory_depth > 1
    trajectory_depth = 1
endif
if shadow_depth < 0
    shadow_depth = 0
endif
if shadow_depth > 0.95
    shadow_depth = 0.95
endif
if peak_ceiling <= 0 or peak_ceiling > 1
    peak_ceiling = 0.95
endif
if reference_distance_meters <= 0
    reference_distance_meters = 1.0
endif
if max_distance_meters <= reference_distance_meters
    max_distance_meters = reference_distance_meters + 1
endif

# v2.0: nothing stopped a distance beyond the maximum, which also let
# the visualization bar run past its frame.
distClamped = 0
if distance_meters > max_distance_meters
    distance_meters = max_distance_meters
    distClamped = 1
endif
if distance_meters < reference_distance_meters
    distance_meters = reference_distance_meters
endif

# === Source ===
# Captured before the form, so a RealTier selected alongside cannot
# disturb which Sound this is.
original = soundIn
name$ = selected$("Sound")
selectObject: original
sampleRate = Get sampling frequency
numChannels = Get number of channels
srcT0 = Get start time
srcT1 = Get end time

if numChannels > 1
    selectObject: original
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: original
    Copy: "ap_mono"
    monoID = selected("Sound")
endif

selectObject: monoID
workT0 = Get start time
if workT0 <> 0
    selectObject: monoID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: monoID
    monoID = shiftedID
endif
selectObject: monoID
Rename: "apsrc"
duration = Get total duration

if duration <= 0
    removeObject: monoID
    exitScript: "Source has zero duration."
endif

# v2.0: Nyquist. At 8 or 16 kHz the 8000 Hz shadow default and the
# 12000 Hz air default sit at or above Nyquist.
nyq = sampleRate / 2
cutoffCap = nyq * 0.95
shadowCut = head_shadow_cutoff_Hz
shadowCapped = 0
if shadowCut > cutoffCap
    shadowCut = cutoffCap
    shadowCapped = 1
endif
airCutRef = air_cutoff_at_reference_Hz
airCapped = 0
if airCutRef > cutoffCap
    airCutRef = cutoffCap
    airCapped = 1
endif

# === Distance ===
# v2.0: named for what it computes. Inverse distance is the physical
# pressure law; the softened curve is what v1.1 actually used while
# calling itself inverse-square.
if use_distance
    if distance_model = 1
        distGain = reference_distance_meters / max(distance_meters, reference_distance_meters)
        distModel$ = "inverse distance"
    else
        distGain = 1 / (1 + 2 * distance_meters / max_distance_meters)
        distModel$ = "softened rolloff"
    endif
else
    distGain = 1
    distModel$ = "off"
endif

# Air absorption, continuous from the reference distance rather than
# switching on as a step at 1 m.
airQ = (distance_meters - reference_distance_meters) / (max_distance_meters - reference_distance_meters)
if airQ < 0
    airQ = 0
endif
if airQ > 1
    airQ = 1
endif
airCut = airCutRef / (1 + airQ * 3)
if airCut > cutoffCap
    airCut = cutoffCap
endif
if airCut < 200
    airCut = 200
endif

maxItdSec = 0
if use_ITD
    maxItdSec = max_ITD_ms / 1000
endif

# ============================================================
# PAN TRAJECTORY
# ============================================================
# One RealTier is the master description of the pan path, whether it
# came from a static value, a built-in shape, or the editor. Everything
# downstream reads from it, so the three routes cannot diverge.

nShape = 200
# Create RealTier takes name, tmin, tmax only - there is no min/max
# range argument. The editor scales to the points it holds, so the
# seeded points below also set the visible range.
Create RealTier: "PanTrajectory", 0, duration
panTier = selected("RealTier")

if pan_mode = 1
    Add point: 0, pan_position
    Add point: duration, pan_position
elsif pan_mode = 8
    # Seed a gentle sweep that also touches -1 and +1, so the editor
    # opens with the full pan range visible and you can drag anywhere
    # inside it without the view rescaling under you.
    Add point: 0, -1
    Add point: duration * 0.25, -0.5
    Add point: duration / 2, 0
    Add point: duration * 0.75, 0.5
    Add point: duration, 1
else
    for k from 0 to nShape
        tt = k * duration / nShape
        uu = k / nShape
        ph = 2 * pi * trajectory_cycles * uu
        if pan_mode = 2
            pv = -1 + 2 * uu
        elsif pan_mode = 3
            pv = 1 - 2 * uu
        elsif pan_mode = 4
            pv = sin(ph)
        elsif pan_mode = 5
            # Oscillation that widens from the centre
            pv = sin(ph) * uu
        elsif pan_mode = 6
            # Oscillation that narrows to the centre
            pv = sin(ph) * (1 - uu)
        else
            # Damped pendulum
            pv = sin(ph) * exp(-2 * uu)
        endif
        Add point: tt, pv * trajectory_depth
    endfor
endif

# v2.2: the drawing tool runs in TWO PASSES rather than pausing.
# Praat will not open a second pause form while the script's own form
# window is up, so beginPause fails here with "cannot have more than
# one pause form at a time". Instead:
#   Pass 1 - no RealTier selected: build a seeded PanTrajectory, open
#            its editor, and stop. You draw at your own pace, with the
#            script no longer running and nothing waiting on you.
#   Pass 2 - select the Sound AND the PanTrajectory, run again: the
#            drawn tier is used as the pan path.
# This is also better than a pause in practice: you can close and
# reopen the editor, audition, and re-run pass 2 as many times as you
# like against the same drawn curve.
drawnPoints = 0
if pan_mode = 8
    if tierIn = 0
        # Pass 1
        selectObject: panTier
        View & Edit
        writeInfoLine: "=== Advanced Stereo Panner - DRAW MODE, PASS 1 OF 2 ==="
        appendInfoLine: ""
        appendInfoLine: "A RealTier called PanTrajectory has been created and opened."
        appendInfoLine: "Its time axis spans the source: 0 to ", fixed$(duration, 3), " s."
        appendInfoLine: ""
        appendInfoLine: "1. Draw the pan path in that editor."
        appendInfoLine: "     -1 = hard left     0 = centre     +1 = hard right"
        appendInfoLine: "   Add points by clicking, drag them, remove them - the seeded"
        appendInfoLine: "   sweep already spans -1 to +1 so the full range is visible."
        appendInfoLine: ""
        appendInfoLine: "2. In the Objects window select BOTH:"
        appendInfoLine: "     the Sound ", name$
        appendInfoLine: "     and the RealTier PanTrajectory"
        appendInfoLine: ""
        appendInfoLine: "3. Run this script again with Pan mode = DRAW YOUR OWN."
        appendInfoLine: "   The drawn curve will be used as the pan path."
        appendInfoLine: ""
        appendInfoLine: "The trajectory object is left in place, so you can redraw and"
        appendInfoLine: "re-run step 3 as often as you like against the same curve."
        removeObject: monoID
        exitScript: "PASS 1 of 2 done. PanTrajectory is open for drawing - see the Info window for the next step."
    else
        # Pass 2: adopt the drawn tier and discard the seeded one
        removeObject: panTier
        panTier = tierIn
        selectObject: panTier
        drawnPoints = Get number of points
        if drawnPoints < 1
            removeObject: monoID
            exitScript: "The selected RealTier has no points. Draw a curve first."
        endif
        tierT1 = Get end time
        if abs(tierT1 - duration) > 0.001
            appendInfoLine: "NOTE: the trajectory spans ", fixed$(tierT1, 3),
                ... " s and the source ", fixed$(duration, 3), " s."
            appendInfoLine: "  Values outside the trajectory hold at its nearest point."
        endif
    endif
endif

# Control grid. Dense enough that the gain curves resolve the path;
# the AmplitudeTier interpolates linearly between these points.
nCtrl = ceiling(duration * 200)
if nCtrl < 100
    nCtrl = 100
endif
if nCtrl > 20000
    nCtrl = 20000
endif

panMin = 2
panMax = -2
panAbsMax = 0
panSum = 0
for k from 0 to nCtrl
    tt = k * duration / nCtrl
    selectObject: panTier
    pv = Get value at time: tt
    if pv = undefined
        pv = 0
    endif
    if pv < -1
        pv = -1
    endif
    if pv > 1
        pv = 1
    endif
    panAt[k] = pv
    if pv < panMin
        panMin = pv
    endif
    if pv > panMax
        panMax = pv
    endif
    if abs(pv) > panAbsMax
        panAbsMax = abs(pv)
    endif
    panSum = panSum + abs(pv)
endfor
panAbsMean = panSum / (nCtrl + 1)

# ============================================================
# PANNING GAINS
# ============================================================
# Conventional: gL = sqrt(1-u), gR = sqrt(u). Already produces a level
#   difference, which is why v1.1 must not add another one on top.
# Bounded ILD: solve the gains FROM the wanted difference, so the ILD
#   is exactly pan * ILD_max and the far ear never reaches zero.
# Both satisfy gL^2 + gR^2 = 1.

procedure panGains: .p
    if panning_model = 1
        .u = (.p + 1) / 2
        .gL = sqrt(1 - .u)
        .gR = sqrt(.u)
    else
        .d = .p * iLD_max_dB
        .r = 10 ^ (.d / 20)
        .den = sqrt(1 + .r * .r)
        .gL = 1 / .den
        .gR = .r / .den
    endif
endproc

if panning_model = 1
    modelName$ = "conventional equal-power"
else
    modelName$ = "bounded psychoacoustic ILD"
endif

# ============================================================
# ITD
# ============================================================
# Output runs to duration + max ITD so the delayed ear is not cut. v1.1
# concatenated silence and extracted 0..duration, which removed the
# last ITD milliseconds of that channel.
outDur = duration + maxItdSec

selectObject: monoID
Create Sound from formula: "apwork", 1, 0, outDur, sampleRate, "0"
workID = selected("Sound")
Formula: "Sound_apsrc(x)"

# Rasterise the pan path to a Sound, so the ITD formula can read it per
# sample. Built by multiplying a unit Sound by an AmplitudeTier holding
# (pan+1)/2, which Praat interpolates linearly, then mapping back.
Create Sound from formula: "apunit", 1, 0, outDur, sampleRate, "1"
unitID = selected("Sound")

Create AmplitudeTier: "apPanTier", 0, outDur
panAmpTier = selected("AmplitudeTier")
for k from 0 to nCtrl
    tt = k * duration / nCtrl
    Add point: tt, (panAt[k] + 1) / 2
endfor
Add point: outDur, (panAt[nCtrl] + 1) / 2

selectObject: unitID, panAmpTier
Multiply
panSoundID = selected("Sound")
Rename: "appan"
Formula: "self * 2 - 1"
removeObject: unitID, panAmpTier

# Left ear is the far ear when the source is to the right (pan > 0).
itdStr$ = fixed$(maxItdSec, 10)

selectObject: workID
Copy: "apL"
chL = selected("Sound")
if use_ITD and maxItdSec > 0
    # v2.0: fractional, time-varying delay. self(t) would read samples
    # this same pass has already overwritten, so the read comes from
    # the untouched source copy instead. Praat interpolates, so the
    # delay is continuous rather than quantised to whole samples.
    Formula: "Sound_apsrc(x - " + itdStr$ + " * max(0, Sound_appan(x)))"
else
    Formula: "Sound_apsrc(x)"
endif

selectObject: workID
Copy: "apR"
chR = selected("Sound")
if use_ITD and maxItdSec > 0
    Formula: "Sound_apsrc(x - " + itdStr$ + " * max(0, -Sound_appan(x)))"
else
    Formula: "Sound_apsrc(x)"
endif

removeObject: workID

# ============================================================
# FAR-EAR HEAD SHADOW
# ============================================================
# Static: move the filter cutoff, as v1.1 did, so that sound is
#   unchanged.
# Trajectory: crossfade between the dry channel and one fixed-cutoff
#   lowpass, since a cutoff cannot be swept inside a single Praat
#   filter call. Reported, so the difference is not a surprise.
shadowMode$ = "off"
if use_head_shadow and shadow_depth > 0

    if isTrajectory = 0
        shadowMode$ = "static, moving cutoff"
        if pan_position > 0
            selectObject: chL
            cutUse = shadowCut * (1 - pan_position * shadow_depth)
            if cutUse < 200
                cutUse = 200
            endif
            Filter (pass Hann band): 0, cutUse, 100
            tmpID = selected("Sound")
            removeObject: chL
            chL = tmpID
            selectObject: chL
            Rename: "apL"
            shadowCutUsed = cutUse
        elsif pan_position < 0
            selectObject: chR
            cutUse = shadowCut * (1 - abs(pan_position) * shadow_depth)
            if cutUse < 200
                cutUse = 200
            endif
            Filter (pass Hann band): 0, cutUse, 100
            tmpID = selected("Sound")
            removeObject: chR
            chR = tmpID
            selectObject: chR
            Rename: "apR"
            shadowCutUsed = cutUse
        else
            shadowCutUsed = shadowCut
        endif
    else
        shadowMode$ = "trajectory, dry/wet crossfade"
        shadowCutUsed = shadowCut

        # Left channel
        selectObject: chL
        Filter (pass Hann band): 0, shadowCut, 100
        lpL = selected("Sound")
        Rename: "apLlp"

        Create AmplitudeTier: "apShadowL", 0, outDur
        shTierL = selected("AmplitudeTier")
        for k from 0 to nCtrl
            tt = k * duration / nCtrl
            Add point: tt, max(0, panAt[k]) * shadow_depth
        endfor
        Add point: outDur, max(0, panAt[nCtrl]) * shadow_depth

        selectObject: lpL, shTierL
        Multiply
        wetL = selected("Sound")
        Rename: "apLwet"

        Create AmplitudeTier: "apDryL", 0, outDur
        dryTierL = selected("AmplitudeTier")
        for k from 0 to nCtrl
            tt = k * duration / nCtrl
            Add point: tt, 1 - max(0, panAt[k]) * shadow_depth
        endfor
        Add point: outDur, 1 - max(0, panAt[nCtrl]) * shadow_depth

        selectObject: chL, dryTierL
        Multiply
        dryL = selected("Sound")
        Rename: "apLdry"

        selectObject: dryL
        Formula: "self + Sound_apLwet(x)"
        removeObject: chL, lpL, wetL, shTierL, dryTierL
        chL = dryL
        selectObject: chL
        Rename: "apL"

        # Right channel
        selectObject: chR
        Filter (pass Hann band): 0, shadowCut, 100
        lpR = selected("Sound")
        Rename: "apRlp"

        Create AmplitudeTier: "apShadowR", 0, outDur
        shTierR = selected("AmplitudeTier")
        for k from 0 to nCtrl
            tt = k * duration / nCtrl
            Add point: tt, max(0, -panAt[k]) * shadow_depth
        endfor
        Add point: outDur, max(0, -panAt[nCtrl]) * shadow_depth

        selectObject: lpR, shTierR
        Multiply
        wetR = selected("Sound")
        Rename: "apRwet"

        Create AmplitudeTier: "apDryR", 0, outDur
        dryTierR = selected("AmplitudeTier")
        for k from 0 to nCtrl
            tt = k * duration / nCtrl
            Add point: tt, 1 - max(0, -panAt[k]) * shadow_depth
        endfor
        Add point: outDur, 1 - max(0, -panAt[nCtrl]) * shadow_depth

        selectObject: chR, dryTierR
        Multiply
        dryR = selected("Sound")
        Rename: "apRdry"

        selectObject: dryR
        Formula: "self + Sound_apRwet(x)"
        removeObject: chR, lpR, wetR, shTierR, dryTierR
        chR = dryR
        selectObject: chR
        Rename: "apR"
    endif
else
    shadowCutUsed = shadowCut
endif

# ============================================================
# AIR ABSORPTION
# ============================================================
airApplied = 0
if use_distance and use_air_absorption and airQ > 0.001
    airApplied = 1
    selectObject: chL
    Filter (pass Hann band): 0, airCut, 200
    tmpID = selected("Sound")
    removeObject: chL
    chL = tmpID
    selectObject: chL
    Rename: "apL"

    selectObject: chR
    Filter (pass Hann band): 0, airCut, 200
    tmpID = selected("Sound")
    removeObject: chR
    chR = tmpID
    selectObject: chR
    Rename: "apR"
endif

# ============================================================
# GAINS  (panning model x distance)
# ============================================================
Create AmplitudeTier: "apGainL", 0, outDur
gTierL = selected("AmplitudeTier")
for k from 0 to nCtrl
    tt = k * duration / nCtrl
    @panGains: panAt[k]
    Add point: tt, panGains.gL * distGain
endfor
@panGains: panAt[nCtrl]
Add point: outDur, panGains.gL * distGain

Create AmplitudeTier: "apGainR", 0, outDur
gTierR = selected("AmplitudeTier")
for k from 0 to nCtrl
    tt = k * duration / nCtrl
    @panGains: panAt[k]
    Add point: tt, panGains.gR * distGain
endfor
@panGains: panAt[nCtrl]
Add point: outDur, panGains.gR * distGain

selectObject: chL, gTierL
Multiply
tmpID = selected("Sound")
removeObject: chL, gTierL
chL = tmpID

selectObject: chR, gTierR
Multiply
tmpID = selected("Sound")
removeObject: chR, gTierR
chR = tmpID

removeObject: panSoundID

# ============================================================
# COMBINE, THEN PEAK CEILING
# ============================================================
selectObject: chL, chR
Combine to stereo
stereo = selected("Sound")
Rename: name$ + "_pan_" + presetName$

# v2.0: attenuate only, never boost. Scale peak always rescaled to the
# target, which is what erased the distance effect in v1.1.
selectObject: stereo
prePeak = Get absolute extremum: 0, 0, "None"
safetyGain = 1
if prePeak > peak_ceiling and prePeak > 0
    safetyGain = peak_ceiling / prePeak
    Formula: "self * " + fixed$(safetyGain, 10)
endif
selectObject: stereo
postPeak = Get absolute extremum: 0, 0, "None"

removeObject: chL, chR

# ============================================================
# REPORT
# ============================================================
@panGains: panAt[0]
gL0 = panGains.gL * distGain
gR0 = panGains.gR * distGain
@panGains: panAbsMax
ildAtMax = 20 * log10(panGains.gR / max(panGains.gL, 1e-12))

writeInfoLine: "=== Advanced Stereo Panner v2.2 ==="
appendInfoLine: "Source: ", name$, "  (", fixed$(duration, 3), " s @ ", sampleRate, " Hz)"
appendInfoLine: "Output duration: ", fixed$(outDur, 3), " s"
if maxItdSec > 0
    appendInfoLine: "  (source length plus the ", fixed$(maxItdSec * 1000, 2),
        ... " ms maximum ITD, so the delayed"
    appendInfoLine: "   ear is not truncated as it was in v1.1)"
endif
appendInfoLine: ""

if isTrajectory = 0
    appendInfoLine: "Pan: STATIC ", fixed$(pan_position, 3), "  (", presetName$, ")"
else
    appendInfoLine: "Pan: TRAJECTORY ", presetName$
    if pan_mode = 8
        appendInfoLine: "  Drawn by hand: ", drawnPoints, " points in the editor."
    else
        appendInfoLine: "  ", fixed$(trajectory_cycles, 2), " cycle(s), depth ",
            ... fixed$(trajectory_depth, 2)
    endif
    appendInfoLine: "  Range ", fixed$(panMin, 3), " to ", fixed$(panMax, 3),
        ... "   mean |pan| ", fixed$(panAbsMean, 3)
    appendInfoLine: "  ", nCtrl, " control points; the gains ride an AmplitudeTier,"
    appendInfoLine: "  so they interpolate at audio rate with no stepping."
endif
appendInfoLine: ""

appendInfoLine: "Panning model: ", modelName$
if panning_model = 1
    appendInfoLine: "  gL = sqrt(1-u), gR = sqrt(u). The sqrt law already creates a"
    appendInfoLine: "  level difference, so no separate ILD is added on top."
    appendInfoLine: "  At hard pan the far ear reaches exactly 0, so its ITD and head"
    appendInfoLine: "  shadow become inaudible - the price of this model."
else
    appendInfoLine: "  Gains solved from the wanted difference: D = pan * ",
        ... fixed$(iLD_max_dB, 1), " dB,"
    appendInfoLine: "  r = 10^(D/20), gL = 1/sqrt(1+r^2), gR = r/sqrt(1+r^2)."
    appendInfoLine: "  gL^2 + gR^2 = 1 and the ILD is exactly D."
    @panGains: 1
    appendInfoLine: "  At hard pan the far ear sits at ", fixed$(panGains.gL, 4),
        ... " rather than 0, so"
    appendInfoLine: "  the ITD and head shadow stay audible."
endif
appendInfoLine: "  ILD at the widest point reached (|pan| ", fixed$(panAbsMax, 3),
    ... "): ", fixed$(ildAtMax, 2), " dB"
appendInfoLine: ""

if use_ITD
    appendInfoLine: "ITD: up to ", fixed$(max_ITD_ms, 3), " ms = ",
        ... fixed$(maxItdSec * sampleRate, 2), " samples at this rate"
    if isTrajectory = 1
        appendInfoLine: "  Time-varying and fractional: the source is read at"
        appendInfoLine: "  x - delay(x) with Praat's interpolation, so the delay is"
        appendInfoLine: "  continuous rather than quantised to whole samples."
    else
        appendInfoLine: "  Constant ", fixed$(abs(pan_position) * max_ITD_ms, 3), " ms on the far ear."
    endif
else
    appendInfoLine: "ITD: off"
endif
appendInfoLine: ""

appendInfoLine: "Far-ear head shadow: ", shadowMode$
if use_head_shadow and shadow_depth > 0
    appendInfoLine: "  Cutoff ", fixed$(shadowCutUsed, 0), " Hz, depth ",
        ... fixed$(shadow_depth, 2)
    if shadowCapped = 1
        appendInfoLine: "  NOTE: cutoff clamped from ", fixed$(head_shadow_cutoff_Hz, 0),
            ... " Hz to 0.95 x Nyquist."
    endif
    appendInfoLine: "  This is a lowpass on the far channel. It is not a full set of"
    appendInfoLine: "  spectral cues: no pinna notches, no elevation, no front/back."
endif
appendInfoLine: ""

if use_distance
    appendInfoLine: "Distance: ", fixed$(distance_meters, 2), " m of ",
        ... fixed$(max_distance_meters, 1), " m max, model = ", distModel$
    if distClamped = 1
        appendInfoLine: "  NOTE: distance clamped to the maximum."
    endif
    appendInfoLine: "  Attenuation ", fixed$(distGain, 4), " = ",
        ... fixed$(20 * log10(max(distGain, 1e-12)), 2), " dB"
    if airApplied = 1
        appendInfoLine: "  Air absorption cutoff ", fixed$(airCut, 0), " Hz",
            ... "   (continuous from the ", fixed$(reference_distance_meters, 1),
            ... " m reference, no step)"
        if airCapped = 1
            appendInfoLine: "  NOTE: air cutoff clamped to 0.95 x Nyquist."
        endif
    else
        appendInfoLine: "  Air absorption: none at the reference distance."
    endif
else
    appendInfoLine: "Distance: off"
endif
appendInfoLine: ""

appendInfoLine: "Output level:"
appendInfoLine: "  Peak before ceiling: ", fixed$(prePeak, 4)
if safetyGain < 1
    appendInfoLine: "  Peak ceiling ", fixed$(peak_ceiling, 3), " exceeded, so both"
    appendInfoLine: "  channels were attenuated by x", fixed$(safetyGain, 4), " (",
        ... fixed$(20 * log10(safetyGain), 2), " dB)."
else
    appendInfoLine: "  Below the ", fixed$(peak_ceiling, 3),
        ... " ceiling, so no attenuation was applied."
endif
appendInfoLine: "  Final peak: ", fixed$(postPeak, 4)
appendInfoLine: "  The ceiling attenuates but never boosts, so distance and pan"
appendInfoLine: "  level survive. v1.1's Scale peak rescaled to the target every"
appendInfoLine: "  time, which made a 30 m source exactly as loud as a 1 m one."
appendInfoLine: ""
appendInfoLine: "This is a psychoacoustic stereo panner for creative headphone or"
appendInfoLine: "loudspeaker use, not an HRTF-based binaural renderer. On speakers"
appendInfoLine: "each ear hears both channels, so there is acoustic crosstalk and"
appendInfoLine: "the two channels are not the two ear signals."

# ============================================================
# VISUALIZATION
# ============================================================
filterCues$ = modelName$
if use_ITD
    filterCues$ = filterCues$ + " + ITD"
endif
if use_head_shadow and shadow_depth > 0
    filterCues$ = filterCues$ + " + Shadow"
endif
if use_distance
    filterCues$ = filterCues$ + " + Dist"
endif

if draw_visualization
    Erase all

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ADVANCED STEREO PANNER v2.2.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if isTrajectory = 0
        panDesc$ = "static pan " + fixed$(pan_position, 2)
    else
        panDesc$ = "trajectory " + presetName$
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... name$
        ... + "  |  " + panDesc$
        ... + "  |  " + modelName$
        ... + "  |  " + fixed$(duration, 2) + " s @ " + string$(sampleRate) + " Hz"

    # ----------------------------------------------------------
    # PANEL A: SPATIAL DIAGRAM  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.72, 3.55
    Select inner viewport: 0.55, 4.00, 0.82, 3.28

    Axes: -1.6, 1.6, -0.6, 1.25
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -0.6, 1.25

    Paint circle (mm): "{0.40, 0.40, 0.40}", -1.2, 0.85, 3.5
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Text: -1.2, "centre", 1.06, "half", "L"
    Paint circle (mm): "{0.40, 0.40, 0.40}", 1.2, 0.85, 3.5
    Text: 1.2, "centre", 1.06, "half", "R"

    Paint circle (mm): "{0.88, 0.80, 0.70}", 0, 0, 5
    Paint circle (mm): "{0.78, 0.68, 0.58}", -0.28, 0.02, 1.8
    Paint circle (mm): "{0.78, 0.68, 0.58}", 0.28, 0.02, 1.8
    Font size: 6
    Colour: "{0.55, 0.45, 0.35}"
    Text: 0, "centre", -0.24, "half", "head"

    # v2.0: the whole path is drawn, not just one point, and the source
    # height follows the distance so the plot shows what was applied.
    srcY = 0.78
    if use_distance
        distFrac = (distance_meters - reference_distance_meters) / (max_distance_meters - reference_distance_meters)
        srcY = 0.30 + 0.55 * (1 - distFrac)
    endif

    if isTrajectory = 1
        Line width: 2
        nDraw = 200
        for k from 1 to nDraw
            u1 = (k - 1) / nDraw
            u2 = k / nDraw
            i1 = round(u1 * nCtrl)
            i2 = round(u2 * nCtrl)
            frac = u2
            Colour: "{" + fixed$(0.22 + frac * 0.60, 2) + ", "
                ... + fixed$(0.45 - frac * 0.10, 2) + ", "
                ... + fixed$(0.80 - frac * 0.55, 2) + "}"
            Draw line: panAt[i1] * 1.15, srcY, panAt[i2] * 1.15, srcY
        endfor
        Line width: 1
        Paint circle (mm): "{0.10, 0.30, 0.85}", panAt[0] * 1.15, srcY, 2.6
        Paint circle (mm): "{0.85, 0.25, 0.10}", panAt[nCtrl] * 1.15, srcY, 2.6
        Font size: 6
        Colour: "{0.35, 0.35, 0.35}"
        Text: 0, "centre", srcY + 0.16, "half", "path: blue start, red end"
    else
        if pan_position < 0
            srcColor$ = "{0.25, 0.50, 0.82}"
        elsif pan_position > 0
            srcColor$ = "{0.82, 0.45, 0.25}"
        else
            srcColor$ = "{0.45, 0.70, 0.45}"
        endif
        Paint circle (mm): srcColor$, pan_position * 1.15, srcY, 4.5
        Line width: 1
        Colour: "{0.30, 0.50, 0.80}"
        Dotted line
        Draw line: pan_position * 1.15, srcY, -0.28, 0.02
        Colour: "{0.80, 0.50, 0.30}"
        Draw line: pan_position * 1.15, srcY, 0.28, 0.02
        Solid line
    endif

    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, -0.45, 0, 1.15
    Solid line

    Colour: "Black"
    Draw inner box
    Font size: 6
    if use_distance
        spatCap$ = "Spatial position  (height = distance, " + fixed$(distance_meters, 1) + " m)"
        Text bottom: "yes", spatCap$
    else
        Text bottom: "yes", "Spatial position"
    endif

    # ----------------------------------------------------------
    # PANEL B: PAN OVER TIME  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.72, 2.08
    Select inner viewport: 4.55, 7.75, 0.82, 1.86

    Axes: 0, duration, -1.15, 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, -1.15, 1.15
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line
    Colour: "{0.90, 0.90, 0.90}"
    Draw line: 0, 1, duration, 1
    Draw line: 0, -1, duration, -1

    Line width: 2
    Colour: "{0.25, 0.45, 0.78}"
    nDrawT = 400
    for k from 1 to nDrawT
        u1 = (k - 1) / nDrawT
        u2 = k / nDrawT
        i1 = round(u1 * nCtrl)
        i2 = round(u2 * nCtrl)
        Draw line: u1 * duration, panAt[i1], u2 * duration, panAt[i2]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.72, 2.08
    Select inner viewport: 4.02, 4.4, 0.74, 2.06
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Pan"
    Select outer viewport: 4.2, 8, 0.72, 2.08
    Select inner viewport: 4.55, 7.75, 0.82, 1.86
    Axes: 0, duration, -1.15, 1.15
    Text bottom: "yes", "Pan path  (-1 left, +1 right)"

    # ----------------------------------------------------------
    # PANEL C: CHANNEL GAINS OVER TIME  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.38, 3.55
    Select inner viewport: 4.55, 7.75, 2.48, 3.28

    gTop = 1.1
    Axes: 0, duration, 0, gTop
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, 0, gTop

    Line width: 1.5
    for k from 1 to nDrawT
        u1 = (k - 1) / nDrawT
        u2 = k / nDrawT
        i1 = round(u1 * nCtrl)
        i2 = round(u2 * nCtrl)
        @panGains: panAt[i1]
        a1 = panGains.gL * distGain
        b1 = panGains.gR * distGain
        @panGains: panAt[i2]
        a2 = panGains.gL * distGain
        b2 = panGains.gR * distGain
        Colour: "{0.25, 0.50, 0.82}"
        Draw line: u1 * duration, a1, u2 * duration, a2
        Colour: "{0.82, 0.45, 0.25}"
        Draw line: u1 * duration, b1, u2 * duration, b2
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 2.38, 3.55
    Select inner viewport: 4.02, 4.4, 2.40, 3.53
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 2.38, 3.55
    Select inner viewport: 4.55, 7.75, 2.48, 3.28
    Axes: 0, duration, 0, gTop
    Text bottom: "yes", "Channel gains  (blue L, orange R)  incl. distance"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.90, 5.05
    Select inner viewport: 0.55, 7.72, 3.98, 4.80

    selectObject: stereo
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    ampMax = resPeak * 1.15
    Axes: 0, outDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -ampMax, ampMax
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, outDur, 0

    selectObject: stereo
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

    selectObject: stereo
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizL, vizR

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 3.90, 5.05
    Select inner viewport: 0.08, 0.52, 3.92, 5.03
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 3.90, 5.05
    Select inner viewport: 0.55, 7.72, 3.98, 4.80
    Axes: 0, outDur, -ampMax, ampMax
    Text top: "no", "Stereo output  (blue = L, orange = R)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.38, 6.18
    Select inner viewport: 0.55, 7.72, 5.44, 6.12
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##  " + filterCues$
        ... + "  |  Out " + fixed$(outDur, 2) + " s"
        ... + "  |  Pan range " + fixed$(panMin, 2) + " to " + fixed$(panMax, 2)

    if use_distance
        distStr$ = fixed$(distance_meters, 1) + " m (" + fixed$(20 * log10(max(distGain, 1e-12)), 1) + " dB, " + distModel$ + ")"
    else
        distStr$ = "off"
    endif
    Text: 0.02, "left", 0.45, "half",
        ... "ILD at widest " + fixed$(ildAtMax, 1) + " dB"
        ... + "  |  ITD max " + fixed$(max_ITD_ms, 2) + " ms"
        ... + "  |  Shadow " + shadowMode$
        ... + "  |  Distance " + distStr$

    if safetyGain < 1
        ceilStr$ = "attenuated x" + fixed$(safetyGain, 3) + " (" + fixed$(20 * log10(safetyGain), 1) + " dB)"
    else
        ceilStr$ = "no attenuation needed"
    endif
    Text: 0.02, "left", 0.18, "half",
        ... "Peak " + fixed$(prePeak, 3) + " -> " + fixed$(postPeak, 3)
        ... + "  |  Ceiling " + fixed$(peak_ceiling, 2) + ": " + ceilStr$
        ... + "  |  Not an HRTF binaural renderer"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 6.28
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================
# v2.2: a drawn trajectory belongs to the user, so it is left in place;
# only a tier this run created is removed.
removeObject: monoID
if pan_mode <> 8
    removeObject: panTier
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="

if play_result
    selectObject: stereo
    Play
endif

selectObject: stereo
