INCLUDE "hardware.inc"
INCLUDE "font.inc"
INCLUDE "font.asm"

SECTION "Header", ROM0[$100]
  jp EntryPoint
  ds $150 - @, 0 ; make room for header

CopyTile:
.loop
  ld a, [de] ; read the byte at address de
  ld [hli], a ; write that byte to VRAM and increment the write pointer
  inc de ; move the read pointer 1 forward as well
  dec bc ; subtract 1 from counter after copying the first byte
  
  ; the CPU can only easily check if an 8-bit register is 0, but not a 16-bit pair
  ; THIS is how we check if the counter reached 1
  ld a, b ; load the high byte of the counter (b) into a
  or c ; if BOTH a = b AND c are 0, then the result is 0

  jr nz, .loop ; if a and/or b is not zero (meaning bc is not 0), loop again

  ret

ClearBG:
  ld hl, $9800 ; set hl to the start of the background grid
  ld bc, $400 ; we must erase $400 (1024) bytes

.clear:
  xor a ; A XOR A = set a to 0
  ld [hli], a ; set the current background grid byte to 0 and increment hl
  dec bc ; decrement the number of bytes left to erase

  ; check if the counter reached 0
  ld a, b ; set a to the high byte
  or c ; if both a = b AND c are 0, then bc is 0
  jr nz, .clear ; if not zero, continue looping

  ret ; otherwise, return

PrintDE:
.loop
  ld a, [de] ; read next tile
  inc de ; move de to next tile

  cp $FF ; check if a is 0 (terminator)
  ret z ; exit if 0

  ; check if a is newline
  cp $FE
  jr z, .skip_to_newline

  ld [hli], a ; write to screen and terminate (hl starts at $9800)

  inc b
  ld a, b
  cp 20 ; end of screen
  jr nz, .loop
  
  ; newline
  ld bc, 12 ; skip the last 12 (32 - 20) grid boxes
  add hl, bc
  ld b, 0
  jr .loop

.skip_to_newline
  ; how many columns left to new line
  ld a, 32
  sub b

  ld c, a
  ld b, 0
  add hl, bc

  jr .loop

EntryPoint:
  ; first, turn off the LCD
  ; we must do this because the screen is like a machine already in the process of printing
  ; we can't interfere while it works; we must turn it off first
  ld a, 0
  ld [rLCDC], a  ; rLCDC is a memory address ($FF40, the LCD control register)
                ; writing 0 to rLCDC disables the screen
                ; using brackets around this address is like dereferencing a pointer

  ; copy a picture into the tile library
  ; VRAM contains a region ($8000-$97FF) that stores raw tile data
  ; each tile is 16 bytes describing an 8x8 image
  ; this memory space is garbage right now, so we must copy our tile into it before drawing
  ld hl, $8000 ; write pointer for placing the tile into VRAM
  ld de, Font ; read pointer for the tile
  ld bc, FontEnd-Font ; loop counter; we must copy 16 times for each byte of a tile

  call CopyTile ; copy the tile to VRAM tile library
  call ClearBG

  ; tile data stores a 2-bit number per pixel (0, 1, 2, or 3)
  ; the palette register declares what those 4 slots actually look like
  ; (white, light gray, dark gray, black)
  ld a, %11100100 ; 11 10 01 00, the normal mapping (each slot maps to itself)
                  ; goes right to left like regular binary
                  ; slot 0 = 00 (white)
                  ; slot 1 = 01 (light gray)
                  ; slot 2 = 10 (dark gray)
                  ; slot 3 = 11 (black)
  ld [rBGP], a  ; rBGP ($FF47) holds 4 groups of 2 bits

  ; the tile is now in VRAM, but we must load it into the background as well
  ; the background is a 32x32 grid of tiles (from the tilemap at $9800-$9BFF)
  ; we must write to this grid to place our picture onto the screen
  ld hl, $9800 ; set hl to $9800 (the start of the background grid) (top-left)

  ld bc, 0  ; COLUMN POINTER/COUNTER USED BY PRINT

  ld de, HelloWorld
  call PrintDE

  ld de, Numbers
  call PrintDE

  ; now everything is in VRAM and background
  ; we must turn the screen back on now
  ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000  ; | is bitwise OR (combines flags together)
                                              ; screen-power bit, background-enabled bit, $8000 mode
  ld [rLCDC], a ; power both the screen and background

.done
  jr .done

HelloWorld:
  db TILE_H, TILE_E, TILE_L, TILE_L, TILE_O
  db TILE_COMMA, TILE_SPACE
  db TILE_W, TILE_O, TILE_R, TILE_L, TILE_D
  db TILE_EXCLP
  db $FF

Numbers:
  db $FE
  db TILE_1, TILE_2, TILE_3, TILE_4, TILE_5
  db TILE_6, TILE_7, TILE_8, TILE_9, TILE_0
  db $FF
