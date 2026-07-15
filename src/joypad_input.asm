INCLUDE "hardware.inc"

SECTION "Header", ROM0[$100]
  jp EntryPoint
  ds $150 - @, 0 ; make room for header

AwaitRelease:
.await
  ld a, $20
  ld [_IO], a

  ld a, [_IO]
  and %1111 ; keep only D-pad bits
            ; this sets the higher nibble bits to 0
  cp %1111 ; will flag Z if only equal (which means all are released because 0 = pressed)
  jr nz, .await ; if NZ (one of them is pressed), continue waiting

  ret ; otherwise, allow next instruction

Read:
  ; D-pad mode (directions)
  ld a, $20
  ld [_IO], a

  ld a, [_IO] ; load $FF00 into a
  and %0001 ; only flag Z if right bit is 1
            ; 0 = pressed, 1 = released
            ; the AND result will be %...1 (NZ) if right is released, and $...0 (Z) if right is pressed
  jr z, .right

  ld a, [_IO]
  and %0010
  jr z, .left

  ld a, [_IO]
  and %0100
  jr z, .up

  ld a, [_IO]
  and %1000
  jr z, .down

  ret

.right
  inc b
  call AwaitRelease
  ret

.left
  inc c
  call AwaitRelease
  ret

.up
  inc d
  call AwaitRelease
  ret

.down
  inc e
  call AwaitRelease
  ret

AwaitVBlank:
.await
  ld a, [rLY] ; LY tells us which scanline is drawing
  cp 144 ; are we at line 144 (VBlank period)?
  jr c, .await
  ret

EntryPoint:
  xor a
  ld b, a
  ld c, a
  ld d, a
  ld e, a

.loop
  call AwaitVBlank
  call Read
  jr .loop

.done
  jr .done
