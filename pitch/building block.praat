# --- pitch up 7 semitones via samplerate trick ---
semitones = 7
ratio = exp((ln(2)/12) * semitones)

orig_sr = Get sampling frequency

# reinterpret sound as faster/slower
Override sampling frequency... (orig_sr * ratio)

# bring back to normal time base
Resample... orig_sr 50
Play
