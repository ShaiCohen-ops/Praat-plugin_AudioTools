# ============================================================
# Praat AudioTools - Random Reich Generator (Auto-Phasing Tool)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Random Reich Generator (Auto-Phasing Tool)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

################################################################
# Harmonic Reich Generator [PRO] - FIXED v16
# 
# Features:
# 1. Cycle-Based Drifting (Mathematical Precision)
# 2. 3-Voice Architecture (Static, Drifting, Anchor/Shadow)
# 3. Analog Tape Flutter (Micro-wobble)
# 4. Zero Junk Left Behind (Improved Cleanup)
################################################################

form Harmonic Reich Generator [PRO]
    comment --- Presets ---
    optionmenu Preset 1
        option Classic Reich (Speech / Unison)
        option Deep Space (Sub-Bass Shadow)
        option Holy Trinity (5th + High Anchor)
        option Broken Tape (Flutter + Random Offset)
        option Manual (Settings below)

    comment --- Source Extraction ---
    real Min_loop_sec 0.6
    real Max_loop_sec 1.5
    
    comment --- Voice 2 (The Drifter) ---
    optionmenu V2_Interval 2
        option Unison
        option Perfect Fifth (+7st)
        option Octave Down
        option Octave Up
    
    comment --- Voice 3 (The Glue) ---
    optionmenu V3_Mode 1
        option None
        option Center Anchor (Unison Static)
        option Low Shadow (Octave Down Static)
        option High Shimmer (Octave Up Static)
    
    comment --- Structure & Feel ---
    positive Cycle_Duration_min 2.0
    
    optionmenu Start_Offset 3
        option 0% (Unison Start)
        option 50% (Anti-Phase)
        option Random
    
    real Flutter_Amount_st 0.05
    positive Total_Duration_min 3.0
endform

# ============================================
# 1. PRESET LOGIC
# ============================================

p_min = min_loop_sec
p_max = max_loop_sec
p_v2$ = v2_Interval$
p_v3$ = v3_Mode$
p_cycle = cycle_Duration_min
p_off$ = start_Offset$
p_flut = flutter_Amount_st

if preset$ = "Classic Reich (Speech / Unison)"
    p_min = 0.5; p_max = 1.0
    p_v2$ = "Unison"; p_v3$ = "None"
    p_cycle = 2.0; p_off$ = "0% (Unison Start)"
    p_flut = 0.0

elsif preset$ = "Deep Space (Sub-Bass Shadow)"
    p_min = 2.0; p_max = 4.0
    p_v2$ = "Unison"; p_v3$ = "Low Shadow (Octave Down Static)"
    p_cycle = 5.0; p_off$ = "50% (Anti-Phase)"
    p_flut = 0.1

elsif preset$ = "Holy Trinity (5th + High Anchor)"
    p_min = 0.8; p_max = 1.2
    p_v2$ = "Perfect Fifth (+7st)"; p_v3$ = "High Shimmer (Octave Up Static)"
    p_cycle = 3.0; p_off$ = "Random"
    p_flut = 0.02

elsif preset$ = "Broken Tape (Flutter + Random Offset)"
    p_min = 0.4; p_max = 0.9
    p_v2$ = "Unison"; p_v3$ = "Center Anchor (Unison Static)"
    p_cycle = 1.5; p_off$ = "Random"
    p_flut = 0.3
endif

# ============================================
# 2. SOURCE EXTRACTION (CLEAN)
# ============================================

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")
selectObject: source_id
total_src_dur = Get total duration

found = 0
attempts = 0
writeInfoLine: "Searching for audio..."

while found = 0 and attempts < 40
    ldur = randomUniform(p_min, p_max)
    st = randomUniform(0, total_src_dur - ldur)
    
    selectObject: source_id
    Extract part: st, st + ldur, "rectangular", 1, "no"
    temp_part_id = selected("Sound")
    
    # Convert to Mono (Creates NEW object)
    Convert to mono
    check_id = selected("Sound")
    
    # Cleanup the stereo extraction immediately
    selectObject: temp_part_id
    Remove
    
    selectObject: check_id
    rms = Get root-mean-square: 0, 0
    if rms > 0.001
        found = 1
        Rename: "Loop_Base"
        loop_base = check_id
    else
        Remove
        attempts = attempts + 1
    endif
endwhile

if found = 0
    exitScript: "Could not find non-silent audio."
endif

selectObject: loop_base
base_sr = Get sampling frequency
dur_base = Get duration

# ============================================
# 3. CALCULATE DRIFT
# ============================================

cycle_sec = p_cycle * 60
loops_in_cycle = cycle_sec / dur_base
drift_ratio = (loops_in_cycle + 1) / loops_in_cycle

appendInfoLine: "Loop: " + fixed$(dur_base, 3) + "s"
appendInfoLine: "Cycle: " + string$(p_cycle) + " min"
appendInfoLine: "Ratio: " + fixed$(drift_ratio, 6)

# ============================================
# 4. PROCESS VOICE 2 (Pitch + Flutter + Drift)
# ============================================

selectObject: loop_base
Copy: "V2_Temp"
v2_id = selected("Sound")

pitch_ratio = 1.0
if p_v2$ = "Perfect Fifth (+7st)"
    pitch_ratio = 1.4983
elsif p_v2$ = "Octave Down"
    pitch_ratio = 0.5
elsif p_v2$ = "Octave Up"
    pitch_ratio = 2.0
endif

if pitch_ratio <> 1.0 or p_flut > 0
    To Manipulation: 0.01, 75, 600
    manip_id = selected("Manipulation")
    
    Extract pitch tier
    pitch_id = selected("PitchTier")
    
    if pitch_ratio <> 1.0
        Formula: "self * " + string$(pitch_ratio)
    endif
    
    if p_flut > 0
        Formula: "self + randomGauss(0, " + string$(p_flut) + ")"
    endif
    
    selectObject: manip_id
    plusObject: pitch_id
    Replace pitch tier
    
    selectObject: manip_id
    Get resynthesis (overlap-add)
    Rename: "V2_Processed"
    
    v2_new = selected("Sound")
    
    # Cleanup V2 Temp objects
    selectObject: v2_id
    plusObject: manip_id
    plusObject: pitch_id
    Remove
    
    v2_id = v2_new
endif

selectObject: v2_id
Override sampling frequency: base_sr * drift_ratio
Resample: base_sr, 50
Rename: "V2_Drifting"
v2_final = selected("Sound")
selectObject: v2_id
Remove

# ============================================
# 5. PROCESS VOICE 3 (The Anchor)
# ============================================

has_v3 = 0
v3_id = 0

if p_v3$ <> "None"
    has_v3 = 1
    selectObject: loop_base
    Copy: "V3_Temp"
    v3_temp = selected("Sound")
    
    v3_ratio = 1.0
    if p_v3$ = "Low Shadow (Octave Down Static)"
        v3_ratio = 0.5
    elsif p_v3$ = "High Shimmer (Octave Up Static)"
        v3_ratio = 2.0
    endif
    
    if v3_ratio <> 1.0
        To Manipulation: 0.01, 75, 600
        manip_id = selected("Manipulation")
        
        Extract pitch tier
        v3_pitch_id = selected("PitchTier")
        
        Formula: "self * " + string$(v3_ratio)
        
        selectObject: manip_id
        plusObject: v3_pitch_id
        Replace pitch tier
        
        selectObject: manip_id
        Get resynthesis (overlap-add)
        Rename: "V3_Final"
        v3_id = selected("Sound")
        
        # Cleanup
        selectObject: manip_id
        plusObject: v3_pitch_id
        plusObject: v3_temp
        Remove
    else
        Rename: "V3_Final"
        v3_id = selected("Sound")
    endif
    
    selectObject: v3_id
    Scale intensity: 65
endif

# ============================================
# 6. BUILD TRACKS
# ============================================

total_sec = total_Duration_min * 60

procedure make_wall .src .len .name$
    selectObject: .src
    Copy: .name$
    .id = selected("Sound")
    .dur = Get duration
    while .dur < .len
        selectObject: .id
        Copy: "tmp"
        .c = selected("Sound")
        selectObject: .id
        plusObject: .c
        Concatenate
        .new = selected("Sound")
        selectObject: .id
        plusObject: .c
        Remove
        .id = .new
        selectObject: .id
        Rename: .name$
        .dur = Get duration
    endwhile
    selectObject: .id
    Extract part: 0, .len, "rectangular", 1, "no"
    .fin = selected("Sound")
    Rename: .name$
    selectObject: .id
    Remove
    selectObject: .fin
endproc

call make_wall loop_base total_sec "Track_1_Static"
t1 = selected("Sound")

call make_wall v2_final total_sec "Track_2_Drift"
t2 = selected("Sound")

t3 = 0
if has_v3
    call make_wall v3_id total_sec "Track_3_Anchor"
    t3 = selected("Sound")
endif

# ============================================
# 7. OFFSET LOGIC
# ============================================

offset_sec = 0
if p_off$ = "50% (Anti-Phase)"
    offset_sec = dur_base * 0.5
elsif p_off$ = "Random"
    offset_sec = randomUniform(0, dur_base)
endif

if offset_sec > 0
    # Trim T2 (Start later)
    selectObject: t2
    Extract part: offset_sec, total_sec, "rectangular", 1, "no"
    Rename: "T2_Trim"
    t2_new = selected("Sound")
    selectObject: t2
    Remove
    t2 = t2_new
    
    # Trim others (Cut end to match length)
    final_len = total_sec - offset_sec
    
    selectObject: t1
    Extract part: 0, final_len, "rectangular", 1, "no"
    t1_new = selected("Sound")
    selectObject: t1
    Remove
    t1 = t1_new
    
    if has_v3
        selectObject: t3
        Extract part: 0, final_len, "rectangular", 1, "no"
        t3_new = selected("Sound")
        selectObject: t3
        Remove
        t3 = t3_new
    endif
endif

# ============================================
# 8. MIXING & CLEANUP (Robust)
# ============================================

selectObject: t1
Rename: "Left"

selectObject: t2
Rename: "Right"

if has_v3
    # Mix V3 into Left
    selectObject: t1
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Left_Final"
    t1_final = selected("Sound")
    
    selectObject: temp_st
    plusObject: t1
    Remove
    t1 = t1_final

    # Mix V3 into Right
    selectObject: t2
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Right_Final"
    t2_final = selected("Sound")
    
    selectObject: temp_st
    plusObject: t2
    Remove
    t2 = t2_final
    
    selectObject: t3
    Remove
endif

selectObject: t1
plusObject: t2
Combine to stereo
Rename: source_name$ + "_ProReich_" + preset$
final_id = selected("Sound")

# Final Cleanup
selectObject: loop_base
plusObject: v2_final
plusObject: t1
plusObject: t2
if has_v3
   plusObject: v3_id
endif
Remove

selectObject: final_id
Play

