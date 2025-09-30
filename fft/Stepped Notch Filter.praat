# ========================================
# VARIATION 6: Stepped Notch Filter
# ========================================
sampling_rate = Get sampling frequency
To Spectrum: "yes"  
Formula: "if col > 2000 and col < 2200 then self[1,col] * 0.1 else if col > 5500 and col < 5800 then self[1,col] * 0.2 else self[1,col] * 0.7 fi fi"
To Sound
Scale peak: 0.9
Play