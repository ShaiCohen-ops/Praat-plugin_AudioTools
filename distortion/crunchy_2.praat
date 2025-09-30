# must have a Sound selected
if not selected ("Sound")
    exit Please select a Sound object first.
endif
Copy...

Formula... if self > 0 then 1 else -1 fi * (0.5 + 0.3 * sin(100 * x)) * if (x mod 0.05 > 0.025) then 1 else 0 fi


Scale peak: 0.99
Play
