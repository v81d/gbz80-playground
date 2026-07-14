INCLUDE "hardware.inc"

SECTION "Header", ROM0[$100]
  jp EntryPoint
  ds $150 - @, 0 ; make room for header
  
MultiplyAB:
  ld c, a ; c is the number to add to a every iteration

.loop
  dec b ; decrement b by 1
  ret z ; return if zero
  add a, c ; else if nz, a = a + c
  jp .loop ; again

DivideAB:
  ld c, 0

.loop
  inc c
  sub a, b
  jp z, .done
  jp .loop

.done
  ld a, c
  ret

EntryPoint:
  ; a / b
  ld a, 200
  ld b, 4
  call DivideAB

.done
  jr .done
