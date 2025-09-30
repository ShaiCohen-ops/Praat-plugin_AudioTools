voices = 4                 ; number of canon entries
delay_s = 0.50             ; seconds between entries
semitone_step = 7          ; step size in semitones
wrap_octave = 1            ; 1 = wrap to 0..11 semitones
start_intensity_dB = 70
intensity_step_dB = -3

if not selected ("Sound")
    exit ("please select a Sound object first.")
endif

orig$ = selected$ ("Sound")

# work on a copy so the original stays untouched
select Sound 'orig$'
Copy: "base"

# original sampling rate (for rate-based pitch shift)
select Sound base
f0 = Get sampling frequency

for v from 1 to voices
    # pitch shift in semitones (wrapped within one octave if enabled)
    s = (v - 1) * semitone_step
    if wrap_octave
        s = s - 12 * floor (s / 12)
    endif
    factor = 2 ^ (s / 12)
    f_override = floor (f0 * factor + 0.5)

    # make pitched voice @ mono 44.1 kHz
    select Sound base
    Copy: "voice_raw"
    select Sound voice_raw
    Override sampling frequency: 'f_override'
    Resample: 44100, 50
    Convert to mono
    Rename: "voice"

    # drop the pre-resample copy
    selectObject: "Sound voice_raw"
    Remove

    # delay via silence + concatenate (both mono @ 44.1k)
    d = (v - 1) * delay_s
    if d > 0
        Create Sound from formula: "pad", 1, 0, 'd', 44100, "0"
        select Sound pad
        plus Sound voice
        Concatenate
        Rename: "voice"
        select Sound pad
        Remove
    endif

    # intensity shaping
    gain_dB = start_intensity_dB + (v - 1) * intensity_step_dB
    select Sound voice
    Scale intensity: 'gain_dB'

    # initialize or merge
    if v = 1
        Rename: "mix"
    endif
    if v > 1
        # ensure both are mono @ 44.1k and equal length before mixing
        select Sound mix
        Resample: 44100, 50
        Convert to mono
        select Sound voice
        Resample: 44100, 50
        Convert to mono

        select Sound mix
        dm = Get end time
        select Sound voice
        dv = Get end time

        if dm < dv
            pad_len = dv - dm
            Create Sound from formula: "pad_end", 1, 0, 'pad_len', 44100, "0"
            select Sound mix
            plus Sound pad_end
            Concatenate
            Rename: "mix"
            select Sound pad_end
            Remove
        endif
        if dv < dm
            pad_len = dm - dv
            Create Sound from formula: "pad_end", 1, 0, 'pad_len', 44100, "0"
            select Sound voice
            plus Sound pad_end
            Concatenate
            Rename: "voice"
            select Sound pad_end
            Remove
        endif

        # pairwise mix then fold to mono
        select Sound mix
        plus Sound voice
        Combine to stereo
        Rename: "tmp_mix"

        select Sound tmp_mix
        Convert to mono
        Scale peak: 0.99
        Rename: "mix"

        selectObject: "Sound voice"
        Remove
    endif
endfor

# finalize output
select Sound mix
Rename: "canon_mix"

# play the result before cleanup
select Sound canon_mix
Play

# --- cleanup: keep only original input and the output
# (assumes your output is named "canon_mix" and your original name is in orig$)
select all
minusObject: "Sound 'orig$'"
minusObject: "Sound canon_mix"
Remove
