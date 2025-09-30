form Karplus-Strong Texture Generator
    choice Texture_type: 1
        button Plucked String
        button Guitar Strum
        button Harp Glissando
        button Metallic Pluck
        button Prepared Piano
        button Sitar Drone
        button Koto Cascade
        button Banjo Roll
        button Dulcimer Shimmer
        button Steel Drum
    positive Duration_(s) 3.0
    positive Pitch_center_(Hz) 220
    real Damping_(0.9-0.999) 0.995
    real Chaos_(0-1) 0.3
endform

sampling_frequency = 44100
delay_samples = round(sampling_frequency / pitch_center)

if texture_type = 1
    sound = Create Sound from formula: "Pluck", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) else self - damping*self[col - delay_samples] fi"
    
elsif texture_type = 2
    sound = Create Sound from formula: "Strum", 1, 0, duration, sampling_frequency,
    ... "if col <= 100 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*(1+0.01*(col mod 3)))] fi"
    
elsif texture_type = 3
    sound = Create Sound from formula: "Glissando", 1, 0, duration, sampling_frequency,
    ... "if col <= 50 then randomGauss(0,1) else self - damping*self[col - round(delay_samples/(1+x*chaos*0.5))] fi"
    
elsif texture_type = 4
    sound = Create Sound from formula: "Metallic", 1, 0, duration, sampling_frequency,
    ... "if col <= 20 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*0.99)] fi"
    
elsif texture_type = 5
    sound = Create Sound from formula: "PreparedPiano", 1, 0, duration, sampling_frequency,
    ... "if col <= 80 then randomGauss(0,1) * sin(col*0.5) else self - damping*self[col - delay_samples] fi"
    
elsif texture_type = 6
    sound = Create Sound from formula: "Sitar", 1, 0, duration, sampling_frequency,
    ... "if col <= 200 then randomGauss(0,0.8) else self - damping*self[col - delay_samples] + 0.2*self[col - round(delay_samples/2)] fi"
    
elsif texture_type = 7
    sound = Create Sound from formula: "Koto", 1, 0, duration, sampling_frequency,
    ... "if col <= 30 then randomGauss(0,1) * exp(-col/10) else self - damping*self[col - round(delay_samples*(2^(floor(x*3)/12)))] fi"
    
elsif texture_type = 8
    sound = Create Sound from formula: "Banjo", 1, 0, duration, sampling_frequency,
    ... "if col <= 15 then randomGauss(0,1) else self - 0.5*self[col - delay_samples] fi"
    
elsif texture_type = 9
    sound = Create Sound from formula: "Dulcimer", 1, 0, duration, sampling_frequency,
    ... "if col <= 60 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*(1+0.3*sin(x*20)))] fi"
    
elsif texture_type = 10
    sound = Create Sound from formula: "SteelDrum", 1, 0, duration, sampling_frequency,
    ... "if col <= 40 then randomGauss(0,1)*sin(col*0.3) else self - damping*(self[col - delay_samples] + 0.3*self[col - round(delay_samples/2.76)]) fi"
endif

selectObject: sound
Scale peak: 0.95
Play