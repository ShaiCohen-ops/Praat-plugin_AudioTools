form Limiter
real Threshold_(0-1) 0.75
endform

wrk = Copy... limited
threshold = threshold

Formula... if abs(self) > threshold then if self > 0 then threshold else -threshold endif else self endif
Scale peak... 0.99
Play