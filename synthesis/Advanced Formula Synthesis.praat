form Advanced Formula Synthesis
    real Duration 10.0
    real Sampling_frequency 44100
    real Base_frequency 120
    real Modulation_depth 0.6
    integer Complexity_level 3
endform

echo Creating Advanced Formula Synthesis...

if complexity_level = 1
    # Simple modulated waveform
    formula$ = "sin(2*pi*'base_frequency'*x * (1 + 'modulation_depth'*0.3*sin(2*pi*2*x))) * (0.7 + 0.3*sin(2*pi*0.1*x))"
    
elsif complexity_level = 2
    # Multiple competing oscillators
    formula$ = "("
    formula$ = formula$ + "sin(2*pi*'base_frequency'*x * (1 + 0.2*sin(2*pi*1.5*x))) + "
    formula$ = formula$ + "0.5*sin(2*pi*'base_frequency'*1.618*x * (1 + 0.3*sin(2*pi*2.5*x))) + "
    formula$ = formula$ + "0.3*sin(2*pi*'base_frequency'*2.718*x * (1 + 0.4*sin(2*pi*0.7*x)))"
    formula$ = formula$ + ") * (0.6 + 0.4*sin(2*pi*0.05*x))"
    
else
    # Complex chaotic system
    formula$ = "("
    formula$ = formula$ + "sin(2*pi*'base_frequency'*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.4*sin(2*pi*1.2*x + 1.5*sin(2*pi*0.3*x)))) + "
    formula$ = formula$ + "0.7*sin(2*pi*'base_frequency'*1.5*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.3*sin(2*pi*2.1*x + 0.8*sin(2*pi*0.5*x)))) + "
    formula$ = formula$ + "0.4*sin(2*pi*'base_frequency'*2.2*x * "
    formula$ = formula$ + "(1 + 'modulation_depth'*0.5*sin(2*pi*0.9*x + 1.2*sin(2*pi*0.2*x))))"
    formula$ = formula$ + ") * (0.5 + 0.5*sin(2*pi*0.08*x)) * exp(-0.3*x/'duration')"
endif

Create Sound from formula... advanced_formula 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Advanced Formula Synthesis complete!