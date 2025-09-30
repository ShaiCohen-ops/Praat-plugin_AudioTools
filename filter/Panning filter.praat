form Panning filter
    comment Please select a stereo file
    positive freq 500
endform

Copy... tmp
Extract all channels
To Spectrum... yes
select Spectrum tmp_ch1
Formula...     if x <freq then self else 0 fi
To Sound
select Spectrum tmp_ch2
Formula...     if x >freq then self else 0 fi
To Sound
select Sound tmp_ch1
plus Sound tmp_ch2
Combine to stereo
Play