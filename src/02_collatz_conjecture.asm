INCLUDE "hardware.inc"

SECTION "Header", ROM0[$100]
  jp EntryPoint
  ds $150 - @, 0 ; make room for header

EvenOrOdd:
  ld b, a
  srl a ; a = a >> 1 (unsigned), old bit 0 goes to carry
  ; carry will be 1 if odd, 0 if even
  ld a, b ; set a back to its original
  ret

Collatz:
ld c, 1

.loop
  cp 1
  jp z, .done
  inc c
  call EvenOrOdd
  jp .iterate

.iterate
  jp c, .odd
  jp .even

.odd
  ; 3a + 1
  ld b, a
  sla a ; a = a << 1
  add a, b
  inc a
  jp .loop

.even
  ; a / 2
  srl a
  jp .loop

.done
  ld a, c
  ret

EntryPoint:
  ; a % 2
  ld a, 100
  call Collatz

.done
  jr .done
