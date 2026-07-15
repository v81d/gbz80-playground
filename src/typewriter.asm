INCLUDE "hardware.inc"
INCLUDE "font.inc"
INCLUDE "font.asm"

SECTION "Variables", WRAM0

CursorX: db
CursorY: db

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
  ld a, [CursorX]
  cp 104 ; at last keyboard column pos?
  ret z ; if so, don't move

  add 8
  ld [CursorX], a

  call AwaitRelease
  ret

.left
  ld a, [CursorX]
  and a ; at start?
  ret z ; if so, don't move

  sub 8
  ld [CursorX], a

  call AwaitRelease
  ret

.up
  ld a, [CursorY]
  cp 8 ; at top?
  ret z ; if so, don't move

  sub 8
  ld [CursorY], a

  call AwaitRelease
  ret

.down
  ld a, [CursorY]
  cp 32 ; at last keyboard row pos?
  ret z ; if so, don't move

  add 8
  ld [CursorY], a

  call AwaitRelease
  ret

AwaitVBlank:
.wait_end
  ld a, [rLY]
  cp 144
  jr nc, .wait_end ; wait until NOT in VBlank

.wait_start
  ld a, [rLY]
  cp 144
  jr c, .wait_start ; wait until next VBlank starts

  ret

DrawCursor:
  ld hl, _OAMRAM
  ; OAM is 4 bits:
  ; _ _ _ _
  ; | | | |
  ; | | | attributes
  ; | | tile number
  ; | X position
  ; Y position

  ; we must offset Y by 16 and X by 8 because of how OAM works on the DMG

  ld a, [CursorY]
  add 16
  ld [hli], a ; sprite Y

  ld a, [CursorX]
  add 8
  ld [hli], a ; sprite X

  ld a, TILE_SEL
  ld [hli], a ; sprite tile

  xor a
  ld [hl], a ; attributes (last bit)

  ret

EntryPoint:
.setup_lcd
  ; first, turn off the LCD
  ; we must do this because the screen is like a machine already in the process of printing
  ; we can't interfere while it works; we must turn it off first
  ld a, 0
  ld [rLCDC], a ; rLCDC is a memory address ($FF40, the LCD control register)
                ; writing 0 to rLCDC disables the screen
                ; using brackets around this address is like dereferencing a pointer

.copy_tiles
  ; copy a picture into the tile library
  ; VRAM contains a region ($8000-$97FF) that stores raw tile data
  ; each tile is 16 bytes describing an 8x8 image
  ; this memory space is garbage right now, so we must copy our tile into it before drawing
  ld hl, $8000 ; write pointer for placing the tile into VRAM
  ld de, Font ; read pointer for the tile
  ld bc, FontEnd - Font ; loop counter; we must copy 16 times for each byte of a tile
                        ; FontEnd - Font calculates how many bytes are between the two labels

  call CopyTile ; copy the tile to VRAM tile library
  call ClearBG

.create_palette
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
  ld [rOBP0], a ; set palette for sprites

.draw_tiles
  ; the tile is now in VRAM, but we must load it into the background as well
  ; the background is a 32x32 grid of tiles (from the tilemap at $9800-$9BFF)
  ; we must write to this grid to place our picture onto the screen
  ld hl, _SCRN0 ; set hl to $9800 (the start of the background grid) (top-left)

  ld bc, 0  ; COLUMN POINTER/COUNTER USED BY PRINT

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- tiles start here

  ld de, TilesDivider
  call PrintDE

  ld de, TilesKeyboardRow0
  call PrintDE

  ; newline
  ld de, Newline
  call PrintDE

  ld de, TilesKeyboardRowQ
  call PrintDE

  ; newline
  ld de, Newline
  call PrintDE

  ld de, TilesKeyboardRowA
  call PrintDE

  ; newline
  ld de, Newline
  call PrintDE

  ld de, TilesKeyboardRowZ
  call PrintDE

  ; newline
  ld de, Newline
  call PrintDE

  ld de, TilesDivider
  call PrintDE

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- tiles end here

  call DrawCursor

.entry
  xor a
  ld [CursorX], a
  ld a, 8
  ld [CursorY], a

.startup
  ; now everything is in VRAM and background
  ; we must turn the screen back on now
  ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_OBJON  ; | is bitwise OR (combines flags together)
                                                            ; screen-power bit, background-enabled bit, $8000 mode, sprite bit
  ld [rLCDC], a ; power both the screen and background

.loop
  call AwaitVBlank ; TODO: might be unnecessary for now?
  call Read
  call DrawCursor
  jr .loop

.done
  jr .done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- tile maps start here

Newline:
  db $FE
  db $FF

TilesKeyboardRow0:
  db TILE_0, TILE_1, TILE_2, TILE_3, TILE_4, TILE_5, TILE_6, TILE_7, TILE_8, TILE_9
  db TILE_HYPHN, TILE_LPREN, TILE_RPREN
  db TILE_BACK
  db $FF

TilesKeyboardRowQ:
  db TILE_Q, TILE_W, TILE_E, TILE_R, TILE_T, TILE_Y, TILE_U, TILE_I, TILE_O, TILE_P
  db TILE_DBQOT, TILE_SGQOT, TILE_PIPE, TILE_FSLSH
  db $FF

TilesKeyboardRowA:
  db TILE_A, TILE_S, TILE_D, TILE_F, TILE_G, TILE_H, TILE_J, TILE_K, TILE_L
  db TILE_EXCLP, TILE_QSTNP, TILE_LBRKT, TILE_RBRKT
  db TILE_ENTER
  db $FF

TilesKeyboardRowZ:
  db TILE_Z, TILE_X, TILE_C, TILE_V, TILE_B, TILE_N, TILE_M
  db TILE_COMMA, TILE_PERIOD, TILE_COLON, TILE_SMCOL, TILE_PLUS, TILE_MINUS
  db TILE_SPIND
  db $FF

TilesDivider:
  db TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN, TILE_HZLIN
  db $FF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- tile maps end here
