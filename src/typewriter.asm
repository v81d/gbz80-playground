INCLUDE "hardware.inc"
INCLUDE "font.inc"
INCLUDE "font.asm"

SECTION "Variables", WRAM0

CursorX: db
CursorY: db
CurrentCharacterPos: dw
CurrentKeyboardRow: db
CurrentKeyboardCol: db

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

.clear
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

AwaitReleaseDPad:
.await
  ld a, %00100000
  ld [_IO], a

  ld a, [_IO]
  and %1111 ; keep only D-pad bits
            ; this sets the higher nibble bits to 0
  cp %1111 ; will flag Z if only equal (which means all are released because 0 = pressed)
  jr nz, .await ; if NZ (one of them is pressed), continue waiting

  ret ; otherwise, allow next instruction

AwaitReleaseActions:
.await
  ld a, %00010000
  ld [_IO], a

  ld a, [_IO]
  and %1100
  cp %1100
  jr nz, .await

  ret

ReadDPad:
  ; D-pad mode (directions)
  ld a, %00100000
  ld [_IO], a

  ld a, [_IO] ; load $FF00 into a
  bit 0, a  ; only flag Z if right bit is 1
            ; 0 = pressed, 1 = released
            ; the AND result will be %...1 (NZ) if right is released, and $...0 (Z) if right is pressed
  jr z, .right

  ld a, [_IO]
  bit 1, a
  jr z, .left

  ld a, [_IO]
  bit 2, a
  jr z, .up

  ld a, [_IO]
  bit 3, a
  jr z, .down

  ret

.right
  ld a, [CurrentKeyboardCol]
  cp 13 ; at last keyboard column pos?
  ret z ; if so, don't move

  inc a
  ld [CurrentKeyboardCol], a

  ld a, [CursorX]
  add 8
  ld [CursorX], a

  call AwaitReleaseDPad
  ret

.left
  ld a, [CurrentKeyboardCol]
  and a ; at start?
  ret z ; if so, don't move

  dec a
  ld [CurrentKeyboardCol], a

  ld a, [CursorX]
  sub 8
  ld [CursorX], a
  
  call AwaitReleaseDPad
  ret

.up
  ld a, [CurrentKeyboardRow]
  and a ; at top?
  ret z ; if so, don't move

  dec a
  ld [CurrentKeyboardRow], a

  ld a, [CursorY]
  sub 8
  ld [CursorY], a

  call AwaitReleaseDPad
  ret

.down
  ld a, [CurrentKeyboardRow]
  cp 3 ; at last keyboard row pos?
  ret z ; if so, don't move

  inc a
  ld [CurrentKeyboardRow], a

  ld a, [CursorY]
  add 8
  ld [CursorY], a

  call AwaitReleaseDPad
  ret

ReadActions:
  ld a, %00010000 ; select mode
  ld [_IO], a

  ld a, [_IO]
  bit 2, a ; select button
  ret nz

.select
  call PrintCurrentCharacter
  call AwaitReleaseActions
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
  ; | x-position
  ; y-position

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

DrawTypingIndicator:
  ; set hl to current char pos
  ld a, [CurrentCharacterPos]
  ld l, a
  ld a, [CurrentCharacterPos + 1]
  ld h, a

  ; text starts at $98C0
  ; bc becomes this
  ld bc, _SCRN0 + (32 * 6)
  ; c is $C0 (192)

  ; subtract $C0 from current char pos
  ld a, l
  sub c ; this might carry if current char pos < $C0
  ld l, a

  ld a, h
  sbc b ; subtract b and carry flag (1 or 0) from a (to compensate for the carry)
  ld h, a
  ; result (hl) should now be the distance between the top of the page and the current location

  ; copy offset to bc
  ld a, l
  ld c, a
  ld a, h
  ld b, a
  ; bc is now the distance as well

  ; y-pos = (offset >> 5) * 8 to get pixels

  ; offset >> 5 = offset // 2^5 = row number
  srl b
  rr c ; must carry the bit that fell off from b
  srl b
  rr c
  srl b
  rr c
  srl b
  rr c
  srl b
  rr c

  ; row * 8 + 48
  ld a, c
  add a
  add a
  add a
  add 48
  ld d, a
  ; d = y-pos

  ; x-pos = (offset AND 31) * 8
  ld a, l
  and %00011111 ; 31 to keep the last 5 bits only (to get the col)
  add a, a
  add a, a
  add a, a
  ld e, a
  ; e = x-pos

  ; write sprite
  ld hl, _OAMRAM + 4 ; +4 for next

  ld a, d
  add 16
  ld [hli], a

  ld a, e
  add 8
  ld [hli], a

  ld a, TILE_TPIND
  ld [hli], a

  xor a
  ld [hl], a

  ret

PrintCurrentCharacter:
  ld a, [CurrentKeyboardRow]

  ; row 0
  and a
  jr z, .row_0

  ; row 1
  cp 1
  jr z, .row_1

  ; row 2
  cp 2
  jr z, .row_2

  ; row 3
  cp 3
  jr z, .row_3

.row_0
  ld hl, TilesKeyboardRow0
  jr .write_char

.row_1
  ld hl, TilesKeyboardRowQ
  jr .write_char

.row_2
  ld hl, TilesKeyboardRowA
  jr .write_char

.row_3
  ld hl, TilesKeyboardRowZ
  jr .write_char

.write_char ; loop through tile arrays to get char data
  ld a, [CurrentKeyboardCol] ; set counter

.loop
  and a ; if a == 0, jump to .done
  jr z, .print

  inc hl ; next character
  dec a
  jr .loop

.print
  ld a, [hl] ; a is now the character to be printed
  ld b, a

  ; get char pos back
  ld a, [CurrentCharacterPos]
  ld l, a
  ld a, [CurrentCharacterPos + 1]
  ld h, a

  ld a, b ; get char back

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- EXCEPTIONS LIST STARTS HERE !!!!

  ; right now, hl is the character pos and a is the char

  cp TILE_BACK
  jr z, .backspace

  ; check if at last pos
  ; last pos is at $9A33 (19, 17)
  ; we actually don't want to let the user fill the last tile because it would push the indicator out
  ld a, h
  cp $9A ; compare with last high byte
  jr c, .print_backspace_not_end ; less than $9A (ok)

  ld a, l
  cp $33 ; compare with last low byte
  ret z

.print_backspace_not_end
  ld a, b ; get char back

  cp TILE_ENTER
  jr z, .enter

  ; check if at last col
  ; if so, don't write to last col and simply create a new line
  ld a, l
  and %00011111 ; last 5 bits is col
  cp 19 ; 19 is last col
  jp nz, .print_char_not_end ; if pos != 19, write the char normally

  ; create a newline
  ld de, 13
  add hl, de

.print_char_not_end
  ld a, b ; get char back again

  cp TILE_SPIND
  jr z, .space

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -- EXCEPTIONS LIST ENDS HERE !!!!
  
  ld [hli], a ; print char
  jr .finalize

.backspace
  ; first pos = $98C0
  ld a, h ; current char pos
  cp $98 ; is first row?
  jp nz, .backspace_not_end ; if not, continue

  ld a, l
  cp $C0 ; is first col?
  ret z ; if so, cancel

.backspace_not_end
  ld a, l
  and %00011111
  jr z, .backspace_back_visible ; if col is 0, skip the extra 12 hidden tiles

  ; normal case: just go back one tile
  dec hl
  ld a, TILE_SPACE
  ld [hl], a
  jr .finalize

.backspace_back_visible
  ld b, 13 ; 12 hidden tiles + the last tile

  ; HL -= 11
  ld a, l
  sub b
  ld l, a

  ld a, h
  sbc 0 ; subtract the carry from the high byte
  ld h, a

  jr .finalize

.enter
  ; check if already at last line
  ; first address at last line = $9A20 (0, 17)
  ld a, h
  cp $9A
  jp c, .enter_not_end ; less than $9A (ok)

  ld a, l
  cp $20  ; we want to check if a (low byte) >= $20
  ret nc  ; only a == val and a > value result in a carry of 0, so nc means >=
          ; if a >= $20, then the pos is already at the last line

.enter_not_end
  ; get current column from hl
  ld a, l
  and %00011111 ; keep only column bits (0-31)

  ld c, a
  ld a, 32
  sub c ; a is now the # of tiles remaining until next row

  ld c, a ; set c to a
  ld b, 0 ; construct bc = c = a

  add hl, bc  ; move hl to start of next row
              ; add bc = c = a to hl

  jr .finalize

.space
  ld a, TILE_SPACE
  ld [hli], a
  jr .finalize

.finalize
  ld a, l
  ld [CurrentCharacterPos], a
  ld a, h
  ld [CurrentCharacterPos + 1], a

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

.entry
  xor a

  ld [CurrentKeyboardRow], a
  ld [CurrentKeyboardCol], a

  ld [CursorX], a
  ld a, 8
  ld [CursorY], a

  ld hl, _SCRN0 + (32 * 6) ; 32 rows * 6 columns to get under the divider
  ld a, l
  ld [CurrentCharacterPos], a
  ld a, h
  ld [CurrentCharacterPos + 1], a

.startup
  ; now everything is in VRAM and background
  ; we must turn the screen back on now
  ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_OBJON  ; | is bitwise OR (combines flags together)
                                                            ; screen-power bit, background-enabled bit, $8000 mode, sprite bit
  ld [rLCDC], a ; power both the screen and background

.loop
  call AwaitVBlank ; TODO: might be unnecessary for now?
  call ReadDPad
  call ReadActions
  call DrawCursor
  call DrawTypingIndicator
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
