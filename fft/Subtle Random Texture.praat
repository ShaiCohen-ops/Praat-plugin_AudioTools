sampling_rate = Get sampling frequency
To Spectrum: "yes"
Formula: "if col < 10000 then self[1,col]*(0.8+0.2*randomUniform(0.5,1)) else self[1,col] fi"
To Sound
Scale peak: 0.85