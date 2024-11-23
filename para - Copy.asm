***************
* PARA.ASM
* Simple Lynx game using Lynxass + new BLL
*
* created : 2024-05-20
* change  : 
****************

; Note: Use mikey/suzy register names in hardware.inc
                include <includes/hardware.inc>
* macros
                include <macros/help.mac>
                include <macros/if_while.mac>
                include <macros/font.mac>
                include <macros/mikey.mac>
                include <macros/suzy.mac>
                include <macros/irq.mac>
                include <macros/newkey.mac>
* variables
                include <vardefs/help.var>
                include <vardefs/font.var>
                include <vardefs/mikey.var>
                include <vardefs/suzy.var>
                include <vardefs/irq.var>
                include <vardefs/newkey.var>

; JH Macros
    ; Copy 16 bit value from one address to the other
		MACRO COPY16      ; <src> <dest>
        lda \0
        sta \1
        lda 1+\0
        sta 1+\1
		ENDM

    ; Set dest addr to 16-bit value 
		MACRO SET16      ; <dest> <value>
        lda #<(\1)
        sta \0
        lda #>(\1)
        sta 1+\0
		ENDM

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
        lda #>(\1)
        sta (\0),y
		ENDM


 BEGIN_ZP
ptr0            ds 2
ptr1            ds 2
ptr2            ds 2
;objectPtr       ds 2            ; JH - Pointer to current game object
scbPtr          ds 2            ; JH - Pointer to curret SCB
 END_ZP

 BEGIN_MEM
                ALIGN 4
screen0         ds SCREEN.LEN
screen1         ds SCREEN.LEN
irq_vektoren    ds 16


; JH - Game objects arrays/structs
MAX_OBJECTS     equ 20
; Game object struct field offsets in SCBs
; (game object data stored in 32-byte SCB block) 
fieldType       equ 24
fieldState      equ 25
fieldX          equ 7                  ; 2 bytes, same as scbFieldX
fieldY          equ 9                  ; 2 bytes, same as scbFieldY
fieldDX         equ 26                 ; 1 byte, object X velocity
fieldDY         equ 27                 ; 1 byte, object Y velocity
fieldFrame      equ 28
fieldCounter    equ 29
OBJECT_STRUCT_SIZE    equ 32            ; adjust if adding/removing fields

; Object types
OTYPE_NONE         equ 0                ; None/inactive object
OTYPE_HELI         equ 1                ; Helicopter
OTYPE_PARA         equ 2                ; Paratrooper while parachuting (or falling)
OTYPE_TROOPER      equ 3                ; Paratropper while on the ground

; Object states
OSTATE_NONE        equ 0                ; ?  (uninitialised state)
OSTATE_LEFT        equ 1                ; Helicopter left
OSTATE_RIGHT       equ 2                ; Helicopter right
OSTATE_CHUTING     equ 3                ; Paratrooper parachuting
OSTATE_FALLING     equ 4                ; Paratrooper falling to his death
OSTATE_GROUND      equ 5                ; Paratrooper on the ground

; Game objects now imbedded in SCBs
;                ALIGN 256
;objects         ds (OBJECT_STRUCT_SIZE * MAX_OBJECTS)

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
                SETRGB titlePal         ; pal
                INITIRQ irq_vektoren
                INITKEY ,_FIREA|_FIREB          ; repeat for A & B
                INITFONT BIGFNT,0,13
                SET_MINMAX 0,0,160,102
                SETIRQ 2, VBL                      ; Vertical blank IRQ
                SETIRQ 0, HBL                      ; Horizontal blank IRQ

; JH - I think this is done just so pseudorandom via AUDIO_A | SHIFTER_L
                lda #%11000
                sta AUDIO_A + AUD_CNTRL1          ; Audio channel 0 register AUD_CNTRL1
                lda #1
                sta AUDIO_A + AUD_BAKUP           ; Audio channel 0 register AUD_BAKUP
                lda #$81
                sta AUDIO_A + FEEDBACK_ENABLE     ; Audio channel 0 register FEEDBACK_ENABLE

                cli
                SCRBASE screen0, screen1          ; Single buffered (for double-buffer, specify 2nd parameter as 2nd screen buffer)
                HOME                              ; Reset HOFF and VOFF
                
                LDA #scbFieldCollRes
                STA COLLOFF                       ; Set SCB coll result offset

                jsr InitAllObjects                ; JH - init objects structs (object data embedded in SCBs)

                lda #0
                jsr SetSCBPointer                 ; Set current SCB pointer to first SCN

; JH - Set up first 2 SCBs
        ; Test using current SCB pointer
        LDY #scbFieldSprctl0
        LDA #(SPRCTL0_4_COL | SPRCTL0_BACKGROUND_NON_COLLIDABLE) 
        STA (scbPtr), Y
        ; Set first SCB "next" to second SCB start
        LDAX SCBTable + 32
        JSR SetSCBNext      
        ; Set first SCB image to title
        LDAX titleSpr
        JSR SetSCBImage  
  

.loop
 ;               jsr ReadKey                      ;; JH - This taken out as it applies key repeat delay
 ;               _IFNE
;.0                jsr ReadKey
;                  bne .0
;.1                jsr ReadKey
;                  beq .1
;                _ENDIF

;                jsr Fire
                ;VSYNC
                SWITCHBUF                   ; Also does a VSYNC first
                LDAY SCBTable                ;image_scb
                jsr DrawSprite              ; In draw_sprite.inc

                lda JOYPAD                  ; Mem location "Cursor" seems to have key repeat applied
                _IFNE                       ; beq .noCursor

                  ; Test using current SCB pointer
                  lda #1
                  jsr SetSCBPointer                 ; Set current SCB pointer to second SCB
                  jsr GetSCBX                       ; AX = SCB X value
                  DEC
                  jsr SetSCBX                       ; SCB X value = AX

                  dec SCBTable + scbFieldScaleX
                  dec SCBTable + scbFieldScaleY

                _ENDIF
.noCursor

                ; Set object 5 type and X pos
                lda #5
                jsr SetSCBPointer
                SETFIELD scbPtr, fieldType, 1
                SETFIELD16 scbPtr, fieldX, 77              ; Set object field (16-bit)

                SET_XY 60,40
                PRINT Hallo

                bra .loop

Hallo:          dc.b "HOT!",0


; JH - Init the game objects
InitAllObjects::
                LDY #(MAX_OBJECTS - 1)
.0                TYA
                  JSR SetSCBPointer
                  JSR ResetObject                 ; does not trash Y
                  DEY
                BPL .0
                RTS

; JH - Reset one game object/SCB (via current scb pointer scbPtr)
ResetObject::
                ; We want to clear the type, state, frame and counter fields
                PHY
                LDY #fieldType         ; NB: must use # even though fiedlType is an equ !
                LDA #0
;                STA (scbPtr),Y
;                 INY
;                STA (scbPtr),Y
;                INY
;                STA (scbPtr),Y
;                INY
;                STA (scbPtr),Y 
.0                STA (scbPtr),Y
                  INY
                  CPY #fieldCounter + 1
                  BNE .0
                PLY
                RTS

; JH - Set "current SCB" pointer to a specific SCB index
; In: A - SCB index  (range 0 to 23 !)
SetSCBPointer::
                PHY
                PHA
                AND #$7                ; A = A mod 8
                TAY                    ; = SCB index mod 8
                LDA scbTableOffsetLo,Y
                STA scbPtr             ; LSB of cbPtr
                PLY                    ; = SCB index
                LDA scbTableOffsetHi,Y
                CLC
                ADC #>(SCBTable)
                STA scbPtr + 1         ; MSB of scbPtr
                PLY
                RTS

; For SetSCBPointer - lo and hi bytes offsets of table N from SCBTable[0] addr  
scbTableOffsetLo:
                dc.b 0, 32, 64, 96, 128, 160, 192, 224
scbTableOffsetHi:
                dc.b 0, 0, 0, 0, 0, 0, 0, 0
                dc.b 1, 1, 1, 1, 1, 1, 1, 1
                dc.b 2, 2, 2, 2, 2, 2, 2, 2
                dc.b 3, 3, 3, 3, 3, 3, 3, 3

; JH - Set "next" pointer of current SCB
; In: AX = addr
SetSCBNext::
                LDY #scbFieldNext         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                TXA
                INY
                STA (scbPtr),Y
                RTS
                
; JH - Set "image" pointer of current SCB
; In: AX = addr
SetSCBImage::
                LDY #scbFieldImage         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                TXA
                INY
                STA (scbPtr),Y
                RTS

; JH - Get X of current SCB
; Out: AX = X position
GetSCBX::
                LDY #scbFieldX         ; NB: must use # even though scbFieldX is an equ !
                LDA (scbPtr),Y
                INY
                LDX (scbPtr),Y
                RTS

; JH - Set X of current SCB
; In: AX = X position
SetSCBX::
                LDY #scbFieldX         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                INY
                STX (scbPtr),Y
                RTS

; JH - Get Y of current SCB
; Out: AX = Y position
GetSCBY::
                LDY #scbFieldY         ; NB: must use # even though scbFieldX is an equ !
                LDA (scbPtr),Y
                INY
                LDX (scbPtr),Y
                RTS

; JH - Set Y of current SCB
; In: AX = Y position
SetSCBY::
                LDY #scbFieldY         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                INY
                STX (scbPtr),Y
                RTS


; JH - SCBs for object engine (with embedded object data)
                ALIGN 256
SCBTable        REPT MAX_OBJECTS
                  dc.b SPRCTL0_16_COL | SPRCTL0_NORMAL        ; SPRCTL0
                  dc.b SPRCTL1_DEPTH_SIZE_RELOAD              ; SPRCTL1
                  dc.b SPRCOLL_DONT_COLLIDE                   ; SPRCOLL
                  dc.w 0                                      ; pointer to next scb start
                  dc.w jetSpr                                 ; pointer to sprite image data
                  dc.w 0                                      ; Sprite X
                  dc.w 0                                     ; SPrite Y
                  dc.w $100                                   ; SPrite X scaling
                  dc.w $100                                   ; Sprite Y scaling
                  dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF
                  dc.b 0                                      ; Collision result (offset 23)
                  dc.b 0                                      ; Game object "type" (offset 24)
                  dc.b 0                                      ; Game object "state" (offset 25)
                  dc.b 0                                      ; Game object "frame" (offset 26)
                  dc.b 0                                      ; Game object "counter" (offset 27)
                  ds 4                                        ; padding/reserved to 32 bytes
                ENDR

; SCB struct field offsets
scbFieldSprctl0       equ 0
scbFieldSprctl1       equ 1 
scbFieldSprColl       equ 2 
scbFieldNext          equ 3
scbFieldImage         equ 5
scbFieldX             equ 7
scbFieldY             equ 9
scbFieldScaleX        equ 11   
scbFieldScaleY        equ 13 
scbFieldPalette       equ 15 
scbFieldCollRes       equ 23

***** VBL / HBL INterrupt handlers

VBL::           jsr Keyboard                    ; read buttons
                stz $fda0                       ; GREEN0 (first hardware palette address)
                END_IRQ

HBL::           inc $fda0                      ; GREEN0 (first hardware palette address)
                END_IRQ


***** CODE/ROUTINE INCLUDES
                include </includes/font.inc>
                include </includes/irq.inc>
                include </includes/font2.hlp>
                include </includes/newkey.inc>
                include </includes/hexdez.inc>
                include </includes/random2.inc>
                include </includes/draw_spr.inc>

//->pal        DP 000,040,003,005,006,007,008,009,00A,00B,00C,109,30b,60D,90E,F0F
pal        DP 000,040,003,005,006,007,008,009,00A,00B,00C,00D,10E,30D,70E,F0F

titlePal
                DP 480, 556, 509, 777, 40C, 50F, 70F, CCC, 90F, A0F, B0F, C0F, D0F, D0F, E0F, FFF};

***** SPRITE DATA

titleSpr
                incbin "titleData.spr"

jetSpr          
                incbin "jet1.spr"

