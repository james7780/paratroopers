***************
* PARA.ASM
* Simple Lynx game using Lynxass + new BLL
*
* created : James Higgs, 2024-05-20 to 2024-??-??
* change  : 
****************
* Rules: (https://en.wikipedia.org/wiki/Sabotage_(video_game))
* 1. Every shot decrements score (if > 0)
* 2. 2 points for shooting parachuter
* 3. 5 points for shooting helicopter or jet
* 4. 25 points for shooting a bomb
* 4. Falling helicopter debris takes out parachuters
* 6. Player loses if base hit by bomb, or paratrooper lands on base, or 4 troopers land on either side of the base


; Note: Use mikey/suzy register names in hardware.inc
                include <includes/hardware.inc>
; Include macros
                include <macros/help.mac>
                include <macros/if_while.mac>
                include <macros/font.mac>
                include <macros/mikey.mac>
                include <macros/suzy.mac>
                include <macros/irq.mac>
                include <macros/newkey.mac>
                include <macros/sound.mac>

; Include variables
                include <vardefs/help.var>
                include <vardefs/font.var>
                include <vardefs/mikey.var>
                include <vardefs/suzy.var>
                include <vardefs/irq.var>
                include <vardefs/newkey.var>
                include <vardefs/sound.var>
                include <vardefs/eeprom.var>

; JH Macros
; JH - Store AX in address \0 (1st arg)
    MACRO STAX
		  STA \0
		  STX 1+\0
		ENDM

    ; ; Copy 16 bit value from one address to the other
    MACRO COPY16      ; <src> <dest>
      LDA \0
      STA \1
      LDA 1+\0
      STA 1+\1
    ENDM

    ; ; Set dest addr to 16-bit value 
		; MACRO SET16      ; <dest> <value>
    ;   lda #<(\1)
    ;   sta \0
    ;   lda #>(\1)
    ;   sta 1+\0
		; ENDM

    ; Set data struct field (ZP pointer + offset) to 8-bit value 
		MACRO SETFIELD      ; <ptr> <offset> <value>
      ldy #<(\1)
      lda #<(\2)
      sta (\0),y
		ENDM

    ; Set data struct field (ZP pointer + offset) to 16-bit value 
		MACRO SETFIELD16      ; <ptr> <offset> <value>
      ldy #<(\1)
      lda #<(\2)
      sta (\0),y
      iny
      lda #>(\2)
      sta (\0),y
		ENDM

    MACRO SETCURRENTSCB   ; <index>     (0 to MAX_OBJECTS - 1)
      lda #(\0)
      jsr SetSCBPointer                 ; Set "current SCB" pointer
    ENDM

; Zero page variables (note - not initilased at runtime)
    BEGIN_ZP
param1          ds 2            ; JH - Use for passing parameters to functions / subroutines
param2          ds 2
param3          ds 2
scbPtr          ds 2            ; JH - Pointer to curret SCB / object
objectIndex     ds 1            ; JH - used when looping thru object list
tempW1          ds 2            ; JH - For 16-bit adds etc
tempW2          ds 2
hblCount        ds 1            ; Which line we are on
frameCount      ds 1            ; game timer (decremented evry VBL)
difficulty      ds 1            ; Game difficulty level (0 to 255) [used to be based on score 0 to 255)
heliTimer       ds 1            ; Helicopter next launch timer
bomberTimer     ds 1            ; Bomber next launch timer
joypadValue     ds 1            ; last read joypad value
gunAngle        ds 1            ; Range 0 to 32, corresponding to 17 different angles
fireDebounce    ds 1            ; fire debounce counter
landedCountLeft ds 1            ; number of troops on the left ground
landedCountRight ds 1           ; number of troops on the right ground
troopersAtBase  ds 1            ; number of troops at base
score           ds 2            ; score (WORD)
hiScore         ds 2            ; high score (WORD)
    END_ZP

; Non zero-page variables / buffers
    BEGIN_MEM
                ALIGN 4
screen0         ds SCREEN.LEN
screen1         ds SCREEN.LEN
collbuffer      ds SCREEN.LEN
irq_vektoren    ds 16

; Game objects now imbedded in SCBs
; See objects.inc
    END_MEM

;        global nexttab
;        global line0,line1,line2,image
;        global ptr0,ptr1,ptr2

                run LOMEM             ; code directly after variables

Start::         START_UP              ; Start-Label needed for reStart. START_UP disables interrupts, timers, sets up stack etc
                CLEAR_MEM
                CLEAR_ZP              ; Clear zero page, and also page 1 (stack) if a parameter is given

                INITMIKEY
                INITSUZY
                SETRGB gamePalette
                INITIRQ irq_vektoren
                INITKEY ,_FIREA|_FIREB          ; repeat for A & B
                INITFONT SMALLFNT, 0, 7       ; BIGFNT,0,13
                SET_MINMAX 0,0,160,102
                SETIRQ 2, VBL                      ; Vertical blank IRQ
                SETIRQ 0, HBL                      ; Horizontal blank IRQ

; JH - I think this is done just so pseudorandom via AUDIO_A | SHIFTER_L
                ;lda #%11000
                ;sta AUDIO_A + AUD_CNTRL1          ; Audio channel 0 register AUD_CNTRL1
                ;lda #1
                ;sta AUDIO_A + AUD_BAKUP           ; Audio channel 0 register AUD_BAKUP
                ;lda #$81
                ;sta AUDIO_A + FEEDBACK_ENABLE     ; Audio channel 0 register FEEDBACK_ENABLE

                cli
                SCRBASE screen0, screen1          ; Single buffered (for double-buffer, specify 2nd parameter as 2nd screen buffer)
                ; Set collision buffer address
                lda #<collbuffer
                sta COLLBAS
                ldx #>collbuffer
                stx COLLBAS+1 ; ScreenBase = draw-buffer
                ; Enable collision  (SPRSYS ($FC92) &= $df)
                ; 42bs note: SPRSYS cannot be read, instead you need to use the shadow register
                LDA _SPRSYS
                AND #$DF
                STA SPRSYS
                STA _SPRSYS
                ; Set SCB coll result offset
                LDA #scbFieldCollRes
                STA COLLOFF
                ; Reset HOFF and VOFF
                HOME                  

                jsr InitAllObjects                ; JH - init objects structs (object data embedded in SCBs)
                                                  ; (Also sets up SCB chain)
                SETCURRENTSCB 0                   ; Set current SCB pointer to first SCB / object

; NB - InitObjects sets up SCB chain for ALL objects in SCBTable
; NB - "Skip" flag is reset for all SCBs, until they are "activated"        

                ; Initialise the BLL sound system
                JSR InitAudio
                ; Reset high score
                JSR ResetHiScore
                ; Read hiscore from eeprom
                LDA #0
                JSR EE_Read                 ; Read 16-bit Word from eeprom addr 0 to I2Cword variable
                COPY16 I2Cword, hiScore

.mainLoop
                JSR ShowTitle
                JSR InitGame
                JSR PlayGame
                JSR GameOver
                JMP .mainLoop

; Score handling routines
ResetScore::
                STZ score
                STZ score + 1
                RTS

ResetHiScore::
                STZ hiScore
                STZ hiScore + 1
                RTS

; Add A to the current 16-bit BCD score
AddScoreBCD::
                SED                 ; Set decimal (BCD) mode
                CLC
                ; Add last 2 digits (with carry)
                ADC score + 1
                STA score + 1
                ; Add first 2 digits
                LDA score
                ADC #0              ; // add carry
                STA score
                CLD                 ; Restore binary mode
                RTS

; Update high score from current score, if it is greater
UpdateHiScore:: ; Compare [hi] byte of score
                LDA score
                CMP hiScore
                BCC .exit             ; score[hi] < hiscore[hi]
                BNE .setHiScore       ; score[hi] > hiscore[hi], no need to check [lo]
                ; Compare [lo] byte
                LDA score+1
                CMP hiScore+1
                BCC .exit             ; score[lo] < hiScore[lo]
.setHiScore
                LDA score
                STA hiScore
                LDA score+1
                STA hiScore+1
                ; Write hiscore to eeprom
                COPY16 hiScore, I2Cword
                LDA #0
                JSR EE_Write                 ; Read 16-bit Word from eeprom addr 0 to I2Cword variable
.exit
                RTS

PrintScore::    ; Draw current score
                SET_XY 70,0
                LDA score
                JSR PrintHex
                SET_XY 80,0
                LDA score+1
                JSR PrintHex
                RTS

; Show title screen
ShowTitle::
                ; Set up SCB chain to show title sprite
                LDAX titleSCB
                LDY #scbFieldNext         ; NB: must use # even though scbFieldX is an equ !
                STA clearSCB,Y
                INY
                TXA
                STA clearSCB,Y
               
.loop           ; Loop until key pressed                
                SWITCHBUF                   ; Also does a VSYNC first
                LDAY clearSCB               ;SCBTable                ;image_scb
                JSR DrawSprite              ; In draw_sprite.inc
                ; Draw last score
                JSR PrintScore
                ; Draw high score
                SET_XY 42,85
                PRINT msgHighScore
                SET_XY 100,85
                LDA hiScore
                JSR PrintHex
                SET_XY 110,85
                LDA hiScore+1
                JSR PrintHex                  
                ; Wait for key press
                LDA JOYPAD
                AND #(JOY_A | JOY_B)        ; Sets Z flag if result = 0
                BEQ .loop                   ; branch if Z = 1 (set by AND)

.1              ; Wait for key release
                LDA JOYPAD
                AND #(JOY_A | JOY_B)
                BNE .1
                RTS

msgHighScore:    dc.b "HIGH SCORE:",0

; Set up a new game
InitGame::      JSR ResetScore
                ;LDA #200
                ;STA difficulty
                STZ difficulty
                STZ landedCountLeft
                STZ landedCountRight
                STZ troopersAtBase
                LDA #128
                STA heliTimer
                STA bomberTimer
                ; Setup player
                LDA #16
                STA gunAngle
                ; Show player base (unskip SCB)
                JSR ShowBase
                ; Set up SCB chain to show base and enemy objects
                LDAX baseSCB
                LDY #scbFieldNext         ; NB: must use # even though scbFieldX is an equ !
                STA clearSCB,Y
                INY
                TXA
                STA clearSCB,Y
                RTS

; Main game loop (game running)
PlayGame::
                SWITCHBUF                   ; Also does a VSYNC first
                LDAY clearSCB               ;SCBTable                ;image_scb
                JSR DrawSprite              ; In draw_sprite.inc
                ; Draw score
                JSR PrintScore

; DEBUG - Display difficulty level
                SET_XY 140,90
                LDA difficulty
                JSR PrintDezA   

                ; Check if troopers have bombed the base (or trooper landed on base)
                LDA troopersAtBase               
                CMP #4
                BCS .baseBombed
                ; Player still operative
                JSR UpdatePlayer
                JSR UpdateFireDebounce
                JSR UpdateObjects           ; Update all objects according to thier behaviours
                JSR CheckNewHeli            ; Check if we should launch a new helicopter
                JSR CheckNewBomber          ; Check if we should launch a bomber
                BRA PlayGame
.baseBombed     ; Game over
                ; Update high score if neccessary
                JSR UpdateHiScore
.end
                RTS

; Game over / base explode routine
GameOver::
                ; Explode the base
                JSR ExplodeBase
                ;JSR ExplodeBase
                ;JSR ExplodeBase
                ; Show game over, wait for keypress
.loop
                SWITCHBUF                   ; Also does a VSYNC first
                SET_XY 56, 40
                PRINT msgGameOver
                ; Wait for key press
                LDA JOYPAD
                AND #(JOY_A | JOY_B)        ; Sets Z flag if result = 0
                BEQ .loop                   ; branch if Z = 1 (set by AND)
.1              ; Wait for key release
                LDA JOYPAD
                AND #(JOY_A | JOY_B)
                BNE .1

                RTS

msgGameOver:    dc.b "GAME OVER",0


; JH - Update the player - check keys and change rotation etc
UpdatePlayer::
                ; 1. check left-right DPAD and adjust angle
                LDA JOYPAD
                STA joypadValue
                BIT #JOY_LEFT                   ; Sets Z flag if result = 0
                BEQ .checkRight                 ; branch if Z = 1 (set by AND)
                ; Rotate anticlockwise
                LDA gunAngle
                BEQ .updateSprite               ; angle is already 0
                DEC gunAngle
                BRA .updateSprite

.checkRight
                LDA joypadValue                 ; in case A altered above
                BIT #JOY_RIGHT
                BEQ .updateSprite               ; AND result = 0
                ; Rotate clockwise
                LDA gunAngle
                CMP #64
                BEQ .updateSprite               ; angle is already at max
                INC gunAngle
                ;BRA .updateSprite                 ; Fall thru

.updateSprite
                ; 2. Set player base sprite image, based on current angle
                LDA gunAngle                 ; 0 -> 32
                LSR
                LSR                             ; divide by 4 (range 0 -> 8)
                ASL                             ; multi by 2 for table word offset
                TAY
                LDA barrelSprPtrs,y                     ; was playerSprPtrs,y
                STA barrelSCB + scbFieldImage
                iNY
                LDA barrelSprPtrs,y                     ; was playerSprPtrs,y
                STA barrelSCB + scbFieldImage + 1

.checkFire
                LDA fireDebounce                ; Fire button has debounce counter
                BNE .end                        ; debounce window still active
                LDA joypadValue                 ; in case A altered above
                BIT #JOY_A
                BEQ .end                        ; AND result = 0
                ; Call fire bullet function
                JSR FireBullet
.end
                RTS

 ; Decrement fire debounce if > 0
UpdateFireDebounce::
                LDA fireDebounce
                BEQ .endFireDebounce
                DEC
                STA fireDebounce
.endFireDebounce
                RTS

; Fire a bullet
FireBullet:
                JSR GetFreeBulletObject             ; Get the next free bullet object (at the end of the objects list)
                CMP #$FF
                BEQ .endFireBullet                  ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_BULLET
                SETFIELD scbPtr, fieldState, OSTATE_BULLET
                SETFIELD scbPtr, fieldCounter, 30   ; BUllet alive for 30 frames
                SETFIELD16 scbPtr, fieldX, 80;      ; NB: bullet offset to end of gun barrel below
                SETFIELD16 scbPtr, fieldY, 85; 
                SETFIELD scbPtr, scbFieldSprColl, 0
                SETFIELD scbPtr, scbFieldCollRes, 0 ; reset collision result
                ; set bullet start position, DX and DY from bulletStart/bulletAngle tables (8-bit DX and DY values)
                LDA gunAngle                 ; 0 -> 32
                LSR
                LSR                             ; divide by 4 (range 0 -> 8)
                STA temp                        ; save our table byte offset
                ; Set bullet start position from the bulletStartX/Y tables
                TAY
                LDA bulletStartX, y
                LDY #fieldX
                STA (scbPtr), y
                LDY temp
                LDA bulletStartY, y
                LDY #fieldY
                STA (scbPtr), y
                ; Now copy bullet DX and DY (velocity) from the DX/DY table
                LDY temp
                LDA bulletAnglesDX, y           ; copy DX LSB to SCB 
                LDY #fieldDX
                STA (scbPtr), y
                LDY temp
                LDA bulletAnglesDY, y
                LDY #fieldDY
                STA (scbPtr), y
                ; Set bullet sprite
                LDAX bulletSpr
                JSR SetSCBImage
                ; Decrement score by 1 (unless it's already 0)
                ;LDA score+1
                ;BEQ .endFireBullet
                ;DEC score+1
                ; Trigger player fire sfx
                JSR TriggerPlayerFireSfx        ; Trashes A, X and Y
                ; Increment difficulty
                LDA #255
                CMP difficulty
                BEQ .endFireBullet
                INC difficulty

.endFireBullet
                ; Reset fire debounce
                LDA #20
                STA fireDebounce
                RTS

; Check if we should launch a new heli
CheckNewHeli::
                LDA heliTimer
                BNE .end
                ; Set heliTimer to current heli launch period
                ; NB: Heli timer is only decremented every 2nd frame!
                ; Difficulty logic:
                ; - As difficulty increases, the minimum timer decreases
                ; - Next heli timer = rand(64) + minimum timer for current dificulty
                ; - Minimum timer is held in a table
                ; - Index of minimum timer is related to score (eg: score / 8)
                JSR Random
                AND #$3F                ; (0 to 63)
                STA temp
                LDA difficulty
                LSR                     ; divide by 16 (can 65C02 do nibble swap?)
                LSR
                LSR
                LSR
                TAY
                LDA heliTimerMin,Y
                CLC
                ADC temp
                STA heliTimer           
                ; Launch a new heli  (param1 = X pos, param2 = DX)
                ; Randomly start fomr left or right of screen
                AND #1
                BEQ .startRight
.startLeft
                LDA #0
                STA param1
                LDAX 1                  ; LDAX always immediate
                STAX param2
                BRA .addHeli
.startRight
                LDA #160
                STA param1
                LDAX -1                 ; LDAX always immediate
                STAX param2
.addHeli
                JSR AddNewHelicopter
.end
                RTS

; Minimum timer for new helicopter (decreases with increasing difficulty)
; NB: Heli timer is only decremented every 2nd frame!
;heliTimerMin    dc.b 100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40, 35, 32, 32
heliTimerMin    dc.b 100, 90, 80, 70, 60, 55, 50, 45, 40, 35, 30, 25, 20, 20, 15, 15

; Check if we should launch a new bomber
CheckNewBomber::
                LDA difficulty
                CMP #200
                BCC .end                  ; Only launch bomber after difficulty gets past 200
                LDA bomberTimer           ; Bomber timer decremented in VBL
                BNE .end
                ; Reset bomber timer
                JSR Random
                ORA #$E0
                STA bomberTimer
                ; Launch bomber   (right to left for now)
                LDA #170
                STA param1
                LDAX -1                 ; LDAX always immediate
                STAX param2
                JSR AddNewBomber
.end
                RTS



; Check if we have 4 troopers on the ground, either side
; Returns 0 if false, 4 if true
CheckLanded::
                LDA landedCountLeft
                ORA landedCountRight
                AND #$FC              ; 0 if both < 4, but also handle top bit set (para landed on base)          
                RTS

; Run base exploding animation
ExplodeBase::
                JSR InitAllObjects                ; reset all enemy objects
                JSR TriggerPlayerExplosionSfx     ; Trashes A, X and Y
                ; Add some fragments
                ; Set up param 1 = x and y pos
                LDA #80
                STA param1
                LDA #90
                STA param1+1
                ; Set up param2 = dx
                LDA #1
                STA param2
                ; Set fragment's dy table start offset
                LDA #0                            ; base explosion dx/dy at table offset 0
                STA param2+1
                ; Add 8 fragments (randomly distributed)
                LDY #7
.0
                  PHY  
                  JSR AddNewFragment
                  SETFIELD scbPtr, fieldCounter, 66   ; extend fragment timeout
                  PLY
                  DEY
                  BEQ .killBase
                  ; Change dx for 2nd half of frags
                  CPY #3
                  BNE .0
                  LDA #-1
                  STA param2
                  BRA .0
.killBase
                ; "kill" player base
                JSR HideBase

                ;Run loop for 180 frames (3 seconds)
                STZ frameCount              ; incremented every VBI                            
.loop
                SWITCHBUF                   ; Also does a VSYNC first
                LDAY clearSCB               ;SCBTable                ;image_scb
                jsr DrawSprite              ; In draw_sprite.inc
                JSR PrintScore
                JSR UpdateObjects           ; Update the fragments
                LDA frameCount
                CMP #180
                BNE .loop

                RTS

; Show player base / gun
; Trashes: A, Y
ShowBase::                
                ; Show player base (unskip SCB)
                LDY #scbFieldSprctl1      ; NB: must use #
                LDA baseSCB,Y
                AND #($FF - SPRCTL1_SKIP)                   ; REMOVE bit 2 ($04)
                STA baseSCB,Y
                LDA barrelSCB,Y
                AND #($FF - SPRCTL1_SKIP)                   ; REMOVE bit 2 ($04)
                STA barrelSCB,Y
                RTS

; Hide player base / gun
; Trshes: A, Y
HideBase::
                ; "kill" player base
                LDY #scbFieldSprctl1      ; NB: must use #
                LDA baseSCB,Y
                ORA #SPRCTL1_SKIP
                STA baseSCB,Y
                LDA barrelSCB,Y
                ORA #SPRCTL1_SKIP
                STA barrelSCB,Y  
                RTS

; Object/SCB handling code
                include "objects.asm"

; Background clear SCB
clearSCB
                dc.b SPRCTL0_16_COL | SPRCTL0_BACKGROUND_SHADOW         ; Writes to collosion buffer, but does not do collision check
                dc.b SPRCTL1_DEPTH_SIZE_RELOAD
                dc.b 0                                      ; 0 to clear collision buffer
                dc.w titleSCB                              ; pointer to next scb start
                dc.w clearSpr                               ; pointer to sprite image data
                dc.w 0                                      ; Sprite X
                dc.w 0                                      ; SPrite Y
                dc.w $A000                                  ; SPrite X scaling
                dc.w $6600                                  ; Sprite Y scaling
                dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF
                dc.b 0                                      ; collision result (not used)

; Title SCB
titleSCB
                dc.b SPRCTL0_16_COL | SPRCTL0_BACKGROUND_NON_COLLIDABLE
                dc.b SPRCTL1_LITERAL | SPRCTL1_DEPTH_SIZE_RELOAD
                dc.b SPRCOLL_DONT_COLLIDE
                dc.w 0                                     ; pointer to next scb start
                dc.w titleSpr                             ; pointer to sprite image data
                dc.w 38                                    ; Sprite X
                dc.w 20                                    ; SPrite Y (base of sprite)
                dc.w $100                                  ; SPrite X scaling
                dc.w $100                                  ; Sprite Y scaling
                dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF
                dc.b 0                                      ; collision result

; PLayer SCB (gun base)
baseSCB
                dc.b SPRCTL0_16_COL | SPRCTL0_BACKGROUND_NON_COLLIDABLE
                dc.b SPRCTL1_LITERAL | SPRCTL1_DEPTH_SIZE_RELOAD
                dc.b SPRCOLL_DONT_COLLIDE
                dc.w barrelSCB                             ; pointer to next scb start
                dc.w baseSpr                               ; pointer to sprite image data
                dc.w 80                                    ; Sprite X
                dc.w 98                                    ; SPrite Y (base of sprite)
                dc.w $100                                  ; SPrite X scaling
                dc.w $100                                  ; Sprite Y scaling
                dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF
                dc.b 0                                      ; collision result

barrelSCB
                dc.b SPRCTL0_16_COL | SPRCTL0_NORMAL
                dc.b SPRCTL1_LITERAL | SPRCTL1_DEPTH_SIZE_RELOAD
                dc.b SPRCOLL_DONT_COLLIDE
                dc.w SCBTable                              ; pointer to next scb start
                dc.w barrelSpr                             ; pointer to sprite image data
                dc.w 81                                    ; Sprite X
                dc.w 90                                    ; SPrite Y (base of sprite)
                dc.w $100                                  ; SPrite X scaling
                dc.w $100                                  ; Sprite Y scaling
                dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF
                dc.b 0  

 ; Sound handling code
                include "audio.asm"                 
 
***** VBL / HBL INterrupt handlers

VBL::           jsr Keyboard                   ; read buttons
                ;stz PALETTE                    ; GREEN0 (first hardware palette address)
                INC frameCount                 ; Increment game frame counter
                LDA #$01
                BIT frameCount
                BEQ .skip
                DEC heliTimer                  ; Count down helicopter launch timer (every 2nd frame)
                DEC bomberTimer                ; Also bomber timer
.skip
                STZ hblCount                   ; Reset HBL counter
                END_IRQ

HBL::           ; Used to draw background colour
                ; Use HCOUNTER instead ?
                PHY
                ;LDY HCOUNTER
                LDY hblCount
                LDA bgColArrayG, Y
                STA PALETTE
                LDA bgColArrayBR, Y
                STA PALETTE+16
                INC hblCount
                PLY
                END_IRQ

; Background gradient colour table


***** CODE/ROUTINE INCLUDES
                include <includes/font.inc>
                include <includes/irq.inc>
                include <includes/font2.hlp>
                include <includes/newkey.inc>
                include <includes/hexdez.inc>
                include <includes/random2.inc>
                include <includes/draw_spr.inc>
                include <includes/sound.inc>
                include <includes/eeprom.inc>

// Bullet angle to DX/DY table (17 angles as per the gun)
bulletAnglesDX  dc.b -4, -4, -4, -3, -3, -2, -2, -1,  0,  1,  2,  2,  3,  3,  4,  4,  4
bulletAnglesDY  dc.b  0, -1, -2, -2, -3, -3, -4, -4, -4, -4, -4, -3, -3, -2, -2, -1,  0


// Bullet start offset (per 17 angles of the gun)
GOX equ 80      ; gun "origin" point
GOY equ 89 
;bulletStartX    dc.b GOX - 10, GOX - 10, GOX - 9, GOX - 8, GOX - 7, GOX - 6, GOX - 4, GOX - 2, GOX
;                dc.b GOX + 2, GOX + 4, GOX + 6, GOX + 7, GOX + 8, GOX + 9, GOX + 10, GOX + 10
;bulletStartY    dc.b GOY, GOY - 2, GOY - 4, GOY - 6, GOY - 7, GOY - 8, GOY - 9, GOY - 10, GOY - 10
;                dc.b GOY - 10, GOY - 9, GOY - 8, GOY - 7, GOY - 6, GOY - 4, GOY - 2, GOY
bulletStartX    dc.b GOX - 8, GOX - 8, GOX - 7, GOX - 6, GOX - 6, GOX - 5, GOX - 4, GOX - 2, GOX
                dc.b GOX + 2, GOX + 4, GOX + 5, GOX + 6, GOX + 6, GOX + 7, GOX + 8, GOX + 8
bulletStartY    dc.b GOY, GOY - 2, GOY - 4, GOY - 5, GOY - 6, GOY - 6, GOY - 7, GOY - 8, GOY - 8
                dc.b GOY - 8, GOY - 7, GOY - 6, GOY - 6, GOY - 5, GOY - 4, GOY - 2, GOY

// Game palette (see "spritesheet2.bmp")
gamePalette     DP 000, 5D4, B3A, 80F, B8F, D4F, A2C, FFF, 888, BF6, F88, 008, 00A, 00B, 00D, 00E

; Background colour gradient - 102 values
                ALIGN 256
bgColArrayG     dc.b 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                dc.b 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                dc.b 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                dc.b 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                dc.b 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                dc.b $0F, $0E, $0C, $0A, $07

;bgColArrayBR    dc.b $00, $00, $00, $00, $00, $00,    $10, $10, $10, $10, $10, $10,   $20, $20, $20, $20, $20, $20
;                dc.b $30, $30, $30, $30, $30, $30,    $40, $40, $40, $40, $40, $40,   $50, $50, $50, $50, $50, $50
;                dc.b $60, $60, $60, $60, $60, $60,    $70, $70, $70, $70, $70, $70,   $80, $80, $80, $80, $80, $80
;                dc.b $90, $90, $90, $90, $90, $90,    $A0, $A0, $A0, $A0, $A0, $A0,   $B0, $B0, $B0, $B0, $B0, $B0
;                dc.b $C0, $C0, $C0, $C0, $C0, $C0,    $D0, $D0, $D0, $D0, $D0, $D0,   $E0, $E0, $E0, $E0, $E0, $E0
;                dc.b $E0, $E0, $E0, $E0, $E0, $E0,    $E0, $E0, $E0, $E0, 0, 0, 0, 0

bgColArrayBR    dc.b $00, $00, $00, $00, $00, $00,    $10, $00, $10, $10, $10, $10,   $20, $10, $20, $20, $20, $20
                dc.b $30, $20, $30, $30, $30, $30,    $40, $30, $40, $40, $40, $40,   $50, $40, $50, $50, $50, $50
                dc.b $60, $50, $60, $60, $60, $60,    $70, $60, $70, $70, $70, $70,   $80, $70, $80, $80, $80, $80
                dc.b $90, $80, $90, $90, $90, $90,    $A0, $90, $A0, $A0, $A0, $A0,   $B0, $A0, $B0, $B0, $B0, $B0
                dc.b $C0, $B0, $C0, $C0, $C0, $C0,    $D0, $C0, $D0, $D0, $D0, $D0,   $E0, $D0, $E0, $E0, $E0, $E0
                dc.b $E0, $E0, $E1, $E2, $E3, $E4,    $E5, $E6, $E7, $E8, 0, 0, 0, 0

***** SPRITE DATA

clearSpr        dc.b 3, 8 , 0, 0

baseSpr         incbin "sprites/base.spr"

BSSIZE equ 134
barrelSpr       incbin "sprites/gunArray.spr"
barrelSprPtrs   dc.w barrelSpr, barrelSpr + BSSIZE, barrelSpr + (BSSIZE * 2), barrelSpr + (BSSIZE * 3), barrelSpr + (BSSIZE * 4)
                dc.w barrelSpr + (BSSIZE * 5), barrelSpr + (BSSIZE * 6), barrelSpr + (BSSIZE * 7), barrelSpr + (BSSIZE * 8),
                dc.w barrelSpr + (BSSIZE * 9), barrelSpr + (BSSIZE * 10), barrelSpr + (BSSIZE * 11), barrelSpr + (BSSIZE * 12),
                dc.w barrelSpr + (BSSIZE * 13), barrelSpr + (BSSIZE * 14), barrelSpr + (BSSIZE * 15), barrelSpr + (BSSIZE * 16)

fragSpr         incbin "sprites/fragArray.spr"       ; 4 sprites in 1 file
FSSIZE equ 46
fragSprPtrs     dc.w fragSpr, fragSpr + FSSIZE, fragSpr + (FSSIZE * 2), fragSpr + (FSSIZE * 3)

bulletSpr       incbin "sprites/bullet.spr"

heli1Spr        incbin "sprites/heli1.spr"
heli2Spr        incbin "sprites/heli2.spr"

chuteSpr        incbin "sprites/chuteArray.spr"
CSSIZE equ 134
chuteSprPtrs    dc.w chuteSpr, chuteSpr + CSSIZE, chuteSpr + (CSSIZE * 2), chuteSpr + (CSSIZE * 3)

trooper1Spr     incbin "sprites/trooper1.spr"         ; trooper standing
fallSpr         incbin "sprites/fall.spr"             ; trooper falling
run1Spr         incbin "sprites/run1.spr"             ; trooper running 1
run2Spr         incbin "sprites/run2.spr"             ; trooper running 2

bomber1Spr      incbin "sprites/bomber1.spr"
bomber2Spr      incbin "sprites/bomber2.spr"
bomberSprPtrs   dc.w bomber1Spr, bomber2Spr
bombSpr         incbin "sprites/bomb.spr"

titleSpr        incbin "sprites/title2.spr"

