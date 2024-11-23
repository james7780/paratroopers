; JH - "Game object behaviour engine" arrays/structs and code
;
; Notes:
; 1. The "SCBs" are 32 bytes, and double as object info structs
;    - Bytes 24 to 29 of the SCB hold "object struct" data
; 2. A standard type "object engine" handles the behaviour (AI) and
;    updating of the objects/SCBs
; 3. For collision purposes, bullets and feagments must come after the
;    other "enemy" objects in the object/SCB array
; 4. SCB "skip bit" (SPRCTL1_SKIP) is used for objects/SCBs that are not "active"
; 

MAX_ENEMIES     equ 15
MAX_BULLETS     equ 8                   ; NB: For correct collision, bullets must be drawn after enemy objects
; NB: Fragments are handled as "bullets" !

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
OBJECT_STRUCT_SIZE    equ 32            ; For easier calculation

; Object types
OTYPE_NONE         equ 0                ; None/inactive object
OTYPE_HELI         equ 1                ; Helicopter
OTYPE_PARA         equ 2                ; Paratrooper while parachuting (or falling)
OTYPE_TROOPER      equ 3                ; Paratropper while on the ground
OTYPE_BOMBER       equ 4                ; Bomber
OTYPE_BOMB         equ 5                ; Bomb
OTYPE_FRAGMENT     equ 6                ; helicopter or explosion fragment
OTYPE_BULLET       equ 7                ; Player bullet

; Object states
OSTATE_NONE        equ 0                ; ?  (uninitialised state)
OSTATE_LEFT        equ 1                ; Helicopter left
OSTATE_RIGHT       equ 2                ; Helicopter right
OSTATE_CHUTING     equ 3                ; Paratrooper parachuting
OSTATE_FALLING     equ 4                ; Paratrooper falling to his death
OSTATE_WAITING     equ 5                ; Paratrooper on the ground
OSTATE_ATTACK      equ 6                ; Paratrooper attacking
OSTATE_DYING       equ 7                ; Dying / exploding
OSTATE_BULLET      equ 8                ; stae for bullet (not really used)

; Collision Ids
COLID_HELI         equ 1
COLID_PARA         equ 2
COLID_BOMBER       equ 3
COLID_BOMB         equ 4

    ; Save current scbPtr to stack
		MACRO PUSHSCBPTR
      LDA scbPtr
      PHA
      LDA scbPtr+1
      PHA
		ENDM

    ; Restore current scbPtr from stack
		MACRO POPSCBPTR
      PLA
      STA scbPtr+1
      PLA
      STA scbPtr
		ENDM

; JH - Init the game objects
InitAllObjects::
                LDY #(MAX_ENEMIES + MAX_BULLETS - 1)
                ; For last SCB, do not update the "next SCB" pointer (should be left as 0)
                TYA
                JSR SetSCBPointer
                JSR ResetObject                 ; does not trash Y
                DEY               
.0                TYA
                  JSR SetSCBPointer
                  JSR ResetObject                 ; does not trash Y
                  ; Also set the "next SCB" pointer for this SCB (unless it is the last SCB)
                  LDAX OBJECT_STRUCT_SIZE
                  STA tempW1
                  STX tempW1 + 1
                  ADDW scbPtr, tempW1           ; tempW1 = scbPtr + tempW1
                  LDA tempW1
                  LDX tempW1 + 1
                  JSR SetSCBNext                ; SCB "next" = AX
                  DEY
                BPL .0
                RTS

; JH - Reset one game object/SCB (via current scb pointer scbPtr)
ResetObject::
                ; We want to clear the type, state, DX, DY, frame and counter fields
                PHY
                ;LDY #fieldType         ; NB: must use # even though fiedlType is an equ !
                LDY #scbFieldCollRes      ; We also want to clear the collision result
                LDA #0
.0                STA (scbPtr),Y
                  INY
                  CPY #fieldCounter + 1
                  BNE .0
                ; We also want to set the "skip" bit in sprctl1
                JSR SkipSprite
                PLY
                RTS

; Find a free enemy object in the object list, then:
; 1. Sets scbPtr if successful
; 2. Returns index of object activated in A (or $FF on fail)
; Out: A = found object index, or -1 on fail
GetFreeEnemyObject::
                ; 1. Find free object (type == OTYPE_NONE)
                ; save scbPtr
                PUSHSCBPTR
                LDX #0
.0                TXA
                  JSR SetSCBPointer
                  LDY #fieldType
                  LDA (scbPtr), Y
                  BEQ .exit                     ; scb.type = 0 (OTYPE_NONE)
                  INX
                  CPX #MAX_ENEMIES
                  BNE .0
                ; If we got here, then no inactive object found, so return $FF
                LDX #$FF              
.exit
                ; restore scbPtr
                POPSCBPTR
                ; Return index in A
                TXA
                RTS

; Find a free bullet object in the object list, then:
; 1. Sets scbPtr if successful
; 2. Returns index of object activated in A (or $FF on fail)
; Out: A = found object index, or -1 on fail
GetFreeBulletObject::
                ; 1. Find free object (type == OTYPE_NONE)
                ; save scbPtr
                PUSHSCBPTR
                LDX #MAX_ENEMIES
.0                TXA
                  JSR SetSCBPointer
                  LDY #fieldType
                  LDA (scbPtr), Y
                  BEQ .exit                     ; scb.type = 0 (OTYPE_NONE)
                  INX
                  CPX #(MAX_ENEMIES + MAX_BULLETS)
                  BNE .0
                ; If we got here, then no inactive object found, so return $FF
                LDX #$FF              
.exit
                ; restore scbPtr
                POPSCBPTR
                ; Return index in A
                TXA
                RTS

; Add a new helicopter object
; IN: param1 = x pos  (byte), param2 = direction (DX) (WORD)
AddNewHelicopter::
                JSR GetFreeEnemyObject               ; Get the next free enemy object
                CMP #$FF
                BEQ .fail                           ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_HELI
                SETFIELD scbPtr, fieldState, OSTATE_RIGHT
                ; Set start X
                LDA param1
                LDX #0
                JSR SetSCBX                         ; Set X pos to param1 (input)
                ; Set start Y
                SETFIELD16 scbPtr, fieldY, 6;      ; Must be even
                SETFIELD scbPtr, scbFieldSprctl0, SPRCTL0_16_COL | SPRCTL0_NORMAL | SPRCTL0_HFLIP     ; hflip sprite
                LDA param1
                BEQ .skip1
                SETFIELD16 scbPtr, fieldY, 17      ; Helis coming from right are on lower level
                SETFIELD scbPtr, scbFieldSprctl0, SPRCTL0_16_COL | SPRCTL0_NORMAL           ; no hflip
.skip1
                ; Set start DX
                LDA param2
                LDX param2 + 1
                JSR SetSCBDX                         ; Set DX to param2 (input)
                SETFIELD scbPtr, scbFieldSprColl, COLID_HELI  ; heli collision number   
                LDAX heli1Spr
                JSR SetSCBImage
                ; Set inital para drop counter
                JSR Random
                AND #$7F
                ORA #$07                    ; Minimum of 7 frames
                LDY #fieldCounter
                STA (scbPtr),Y
.fail
                RTS

; Add a new trooper object
; IN: param1 = x pos  (byte)
AddNewTrooper::
                JSR GetFreeEnemyObject               ; Get the next free enemy object
                CMP #$FF
                BEQ .fail                           ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_PARA
                SETFIELD scbPtr, fieldState, OSTATE_FALLING
                LDA param1
                LDX #0
                JSR SetSCBX                         ; Set X pos to temp var (input)
                SETFIELD16 scbPtr, fieldY, 14;      ; Must be even
                SETFIELD scbPtr, fieldDX, 0
                SETFIELD scbPtr, fieldDY, 1;        ; initial falling velocity
                SETFIELD scbPtr, scbFieldSprColl, COLID_PARA ; collision number 
                LDAX trooper1Spr
                JSR SetSCBImage
.fail
                RTS

; Add a new bomber object
; IN: param1 = x pos  (byte), param2 = direction (DX) (WORD)  (NOT YET IMPLMENTED!)
AddNewBomber::
                JSR GetFreeEnemyObject               ; Get the next free enemy object
                CMP #$FF
                BEQ .fail                           ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_BOMBER
                SETFIELD scbPtr, fieldState, OSTATE_LEFT
                ; Make sure hflip is not set
                SETFIELD scbPtr, scbFieldSprctl0, SPRCTL0_16_COL | SPRCTL0_NORMAL           ; no hflip
                ; Set start X
                LDA param1
                LDX #0
                JSR SetSCBX                         ; Set X pos to param1 (input)
                ; Set start Y
                SETFIELD16 scbPtr, fieldY, 25 
                ; Set start DX
                LDA param2
                LDX param2 + 1
                JSR SetSCBDX                         ; Set DX to param2 (input)
                SETFIELD scbPtr, scbFieldSprColl, COLID_BOMBER  ; bomber collision number   
                LDAX bomber1Spr
                JSR SetSCBImage
.fail
                RTS

; Add a new bomb object
; IN: param1 = x pos  (byte)
AddNewBomb::
                JSR GetFreeEnemyObject               ; Get the next free enemy object
                CMP #$FF
                BEQ .fail                           ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_BOMB
                SETFIELD scbPtr, fieldState, OSTATE_FALLING
                LDA param1
                LDX #0
                JSR SetSCBX                         ; Set X pos to temp var (input)
                SETFIELD16 scbPtr, fieldY, 27;      ; Must be even
                SETFIELD scbPtr, fieldDX, 0
                SETFIELD scbPtr, fieldDY, 1;        ; initial falling velocity
                SETFIELD scbPtr, scbFieldSprColl, COLID_BOMB ; collision number 
                LDAX bombSpr
                JSR SetSCBImage
.fail
                RTS

; Add a new fragment
; In: param1 = x pos  (byte) & y pos (byte)
; In: param2 = dx (byte) & fragment dy table start offset
AddNewFragment:
                JSR GetFreeBulletObject             ; Get the next free bullet/fragment object (at the end of the objects list)
                CMP #$FF
                BEQ .endNewFragment                 ; NO EMPTY SCB slot found!
                JSR SetSCBPointer                   ; set current SCB to the found one
                JSR ResetObject                     ; 
                JSR UnskipSprite                    ; so the sprite is drawn
                SETFIELD scbPtr, fieldType, OTYPE_FRAGMENT
                SETFIELD scbPtr, fieldCounter, 45   ; Fragment alive for 40 frames
                SETFIELD scbPtr, scbFieldSprColl, 0
                SETFIELD scbPtr, scbFieldCollRes, 0 ; reset collision result
                ; set fragment start position, DX and DY from param1 and param2
                JSR Random
                AND #7                              ; We want random number 0 - 7
                STA temp
                TAY
                LDA fragOffsetX, Y                  ; 0 - 7
                STA temp+1
                LDA param1                          ; We want frag x pos - param1 + random
                CLC
                ADC temp+1
                LDX #0
                JSR SetSCBX                         ; Set X pos to param1 lo byte + random
                LDY temp
                LDA fragOffsetY, Y                  ; 0 - 7
                STA temp+1               
                LDA param1+1                        ; We want frag y pos - param1+1 + random
                CLC
                ADC temp+1
                ;LDX #0                             ; still 0
                JSR SetSCBY                         ; Set Y pos to param1 hi byte
                ; Set fragment horiz direction
                LDY #fieldState
                LDA #OSTATE_RIGHT
                STA (scbPtr),Y                      ; fieldState 0 = frags go right
                LDA param2                          ; heli dx
                BPL .notNeg
                LDA #OSTATE_LEFT
                STA (scbPtr), Y                     ; fieldState 1 = frags go left
.notNeg
                ; Set "frame" field as start position in fragment path (dx/dy) tables
                LDA temp                            ; 0 - 7
                CLC
                ADC param2+1                        ; differs for heli and base fragments
                LDY #fieldFrame
                STA (scbPtr),Y
                ; Set fragment sprite ("random" from 4 sprites)
                LDA temp
                AND #3
                ASL
                TAY
                LDA fragSprPtrs, Y
                LDX fragSprPtrs+1, Y
                JSR SetSCBImage
.endNewFragment
                RTS

; Fragment start offset table (used by AddNewFragment)
fragOffsetX     dc.b -8, -6, -4, -2,  2,  4,  6,  8
fragOffsetY     dc.b -2,  3,  0,  0, -4,  4, -1,  1

; Add fragments based on the current object
; MUST restore the current object scbPtr when finished
AddFragments::
                ; Save current scbPtr
                PUSHSCBPTR

                ; Set up param 1 = x and y pos
                LDY #fieldX
                LDA (scbPtr),Y
                STA param1
                LDY #fieldY
                LDA (scbPtr),Y
                STA param1+1
                ; Set up param2 = dx
                LDY #fieldDX
                LDA (scbPtr),Y
                STA param2
                ; Set fragment's dy table start offset
                LDA #20
                STA param2+1
                ; Add 4 fragments (randomly distributed)
                JSR AddNewFragment
                JSR AddNewFragment
                JSR AddNewFragment                                
                JSR AddNewFragment

                ; Restore current scbPtr
                POPSCBPTR          
                RTS

; JH - Run one tick for all objects
;      Run thru all objects and applies behavours to each if it is active
UpdateObjects::
                STZ objectIndex
.0              LDA objectIndex
                JSR SetSCBPointer               ; select object A
                LDY #fieldType
                LDA (scbPtr),Y
                BEQ .next                       ; type = OTYPE_NONE
                ; PS: We could have a jump table here ?
.isBullet       CMP #OTYPE_BULLET
                BNE .isHeli
                JSR UpdatePlayerBullet
                BRA .next
.isHeli         CMP #OTYPE_HELI
                BNE .isPara
                JSR UpdateHeli
                BRA .next
.isPara         CMP #OTYPE_PARA
                BNE .isTrooper
                JSR UpdatePara
                BRA .next
.isTrooper      CMP #OTYPE_TROOPER
                BNE .isFragment
                JSR UpdateTrooper
                BRA .next
.isFragment     CMP #OTYPE_FRAGMENT
                BNE .isBomber
                JSR UpdateFragment
                BRA .next
.isBomber       CMP #OTYPE_BOMBER
                BNE .isBomb
                JSR UpdateBomber
                BRA .next
.isBomb         CMP #OTYPE_BOMB
                BNE .next
                JSR UpdateBomb
                BRA .next

.next           ; Decrement this objects counter
                LDY #fieldCounter
                LDA (scbPtr),Y
                DEC
                STA (scbPtr),Y
                ; Next object
                INC objectIndex
                LDA objectIndex
                CMP #(MAX_ENEMIES + MAX_BULLETS)
                BNE .0                          ; next object
                RTS   

; Apply helicopter behaviour to the current object/SCB
UpdateHeli::
                ; Only move every 2nd frame
                LDY #fieldCounter
                LDA (scbPtr),Y
                AND #1
                BEQ .checkDrop                  ; check drop every frame as counter is decremented every frame

                ; Update sprite every 4th frame
                LDA (scbPtr),Y
                LSR
                AND #1
                BEQ .skip1
                LDAX heli1Spr
                BRA .skip2
.skip1          LDAX heli2Spr
.skip2          JSR SetSCBImage

.checkHeliState ; Check for heli state
                LDY #fieldState
                LDA (scbPtr),Y
                BEQ .end                       ; state = OSTATE_NONE  (invalid?)
                ; PS: We could have a jump table here ?
.isLeft         CMP #OSTATE_LEFT
                BNE .isRight
                ; Move left
                JSR MoveObjectX               ; update X by DX
                ; Is AX = 0?
                JSR GetSCBX                   ; need this as SetSCBX trashes A
                CMP #252
                BCC .checkDrop                ; < 252 (ie not -1 or -2 or -3)
                ; End of heli run (heli off left edge of screen)
                JSR ResetObject
                BRA .end                

.isRight        CMP #OSTATE_RIGHT
                BNE .isDying
                ; Move right
                JSR MoveObjectX               ; update X by DX
                ; Is AX = 170?
                JSR GetSCBX                   ; need this as SetSCBX trashes A
                CMP #170      
                BCC .checkDrop                ; < 160
                ; End of heli run (heli off rigth edge of screen)
                JSR ResetObject
                BRA .end                 

.isDying        CMP #OSTATE_DYING
                BNE .end
                ; TODO - Do heli dying stuff here
                JSR ResetObject
                BRA .end

                ; Tiem to drop a trooper?
.checkDrop      LDY #fieldCounter
                LDA (scbPtr),Y
                BNE .end
                ; First reset counter for next para drop
                JSR Random
                AND #$7F
                ORA #$0F                    ; Minimum of 15 frames
                STA (scbPtr), Y
                ; Avoid dropping trooper too near the edge of the screen
                LDY #fieldX
                LDA (scbPtr),Y
                CMP #4
                BCC .end
                CMP #156
                BCS .end
                ; Add the new paratrooper  (changes scbPtr!)                
                STA param1
                PUSHSCBPTR
                JSR AddNewTrooper               ; Changes scbPtr !
                POPSCBPTR

.end
                RTS

; Apply parachuter behaviour to the current object/SCB
UpdatePara::
                LDY #fieldState
                LDA (scbPtr),Y
                ;BEQ .end                       ; state = OSTATE_NONE  (invalid?)
                ; PS: We could have a jump table here ?
.isChuting      CMP #OSTATE_CHUTING
                BNE .isFalling
                ; Parachuting
                ; Only move every 4th frame
                LDY #fieldCounter
                LDA (scbPtr),Y
                STA temp
                AND #3
                BNE .skip1                     ; could actually skip to end?
                JSR MoveObjectY                ; UPdate object Y from DY
                ; Set para sprite frame (1 of 4)
                LDA temp
                ROR                            ; ignore bottom 2 bits as they wil be 0
                ROR
                ROR
                AND #3                         ; limit to 4 values
                ASL
                TAY
                LDA chuteSprPtrs, Y
                LDX chuteSprPtrs+1, Y
                JSR SetSCBImage                
.skip1          ; Is Y = 90?
                JSR GetSCBY                   ; need this as SetSCBX trashes A
                CMP #95
                BNE .end
                ; TODO - Switch to "trooper" type/state
                ;SETFIELD scbPtr, fieldState, OSTATE_FALLING    ; switch to "falling" movement
                ;SETFIELD scbPtr, fieldDY, 2                  ; Speed up fall
                ;SETFIELD16 scbPtr, fieldY, 0                    ; reset back to top pf screen
                SETFIELD scbPtr, fieldState, OSTATE_DYING    ; terminate!
                ; Did we land on the base?
                LDY #scbFieldX
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC #80                         ; our player base X
                BCS .positive
                INC landedCountLeft             ; keep count of how many troops landed 
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
                BRA .abs
.positive
                INC landedCountRight            ; keep count of how many troops landed 
.abs
                CMP #12                         ; A < 12 ?
                BCS .landed                        ; No
                ; Handle para landing on base (make player inactive)
                JSR LandedOnBase       
                BRA .end
.landed
                ; Paratrooper has landed - turn into ground trooper
                JSR ConvertToTrooper               
                BRA .end

.isFalling      CMP #OSTATE_FALLING
                BNE .isDying
                ; Falling
                JSR MoveObjectY
                ; Is Y = 40?
                JSR GetSCBY                   ; need this as SetSCBX trashes A
                CMP #40      
                BNE .isSplatting
                SETFIELD scbPtr, fieldState, OSTATE_CHUTING    ; switch to "chuting" movement
                SETFIELD scbPtr, fieldDY, 1                  ; Slow down the fall
                LDAX chuteSpr   ; now set above in .isChuting
                JSR SetSCBImage                
                BRA .end
.isSplatting    ; Have we fallen to the ground?
                CMP #95     
                BCC .end
                JSR TriggerSplatSfx
                LDA #OSTATE_DYING             ; for fallthough to next line - kill this object

.isDying        CMP #OSTATE_DYING
                BNE .end
                JSR ResetObject
                BRA .end
.end
                RTS

; Convert para to trooper
ConvertToTrooper::
                SETFIELD scbPtr, fieldType, OTYPE_TROOPER
                SETFIELD scbPtr, fieldState, OSTATE_WAITING
                LDAX trooper1Spr
                JSR SetSCBImage
                RTS

; Apply trooper behaviour to the current object/SCB
UpdateTrooper::
                ; If we have landed 4 or more troopers on either side, then attack
                ; Only move every 4th frame
                LDY #fieldCounter
                LDA (scbPtr),Y
                AND #3
                BNE .end
                ; Are we on left or right of base?
                LDY #scbFieldX
                LDA (scbPtr),Y
                CMP #80
                BEQ .end                        ; already at base
                SEC                             ; ?
                SBC #80                         ; our player base X
                BCS .trooperRight
.trooperLeft
                LDA landedCountLeft
                CMP #4
                BMI .end
                ; More than 4 troopers on left of base, so move this trooper right
                LDA (scbPtr),Y
                INC ;A
                STA (scbPtr),Y
                CMP #80
                BNE .setTrooperFrame
                INC troopersAtBase
                BRA .end
.trooperRight
                LDA landedCountRight
                CMP #4
                BMI .end
                ; More than 4 troopers on right of base, so move this trooper left
                LDA (scbPtr),Y
                DEC ;A
                STA (scbPtr),Y
                CMP #80
                BNE .setTrooperFrame
                INC troopersAtBase
                BRA .end
.setTrooperFrame
                ; Set "running" frame 1 or 2
                BIT #2
                BEQ .frame2
                LDAX run1Spr
                JSR SetSCBImage
                JSR TriggerTrooperMoveSfx
                BRA .end
.frame2
                LDAX run2Spr
                JSR SetSCBImage
.end
                RTS

; Apply bomber behaviour to the current object/SCB
UpdateBomber::
                ; Only move every 2nd frame
                ;LDY #fieldCounter
                ;LDA (scbPtr),Y
                ;AND #1
                ;BEQ .end

                ; Update sprite every 4th frame
                LDY #fieldCounter
                LDA (scbPtr),Y
                LSR
                AND #1
                BEQ .skip1
                LDAX bomber1Spr
                BRA .skip2
.skip1          LDAX bomber2Spr
.skip2          JSR SetSCBImage

.checkState     ; Check bomber state
                LDY #fieldState
                LDA (scbPtr),Y
                BEQ .end                       ; state = OSTATE_NONE  (invalid?)
                ; PS: We could have a jump table here ?
.isLeft         CMP #OSTATE_LEFT
                BNE .isRight
                ; Move left
                JSR MoveObjectX               ; update X by DX
                ; Is AX = 0?
                JSR GetSCBX                   ; need this as SetSCBX trashes A
                CMP #252
                BCC .checkDrop                ; < 252 (ie not -1 or -2 or -3)
                ; End of bomber run (bomber off left edge of screen)
                JSR ResetObject
                BRA .end                

.isRight        CMP #OSTATE_RIGHT
                BNE .isDying
                ; Move right
                JSR MoveObjectX               ; update X by DX
                ; Is AX = 170?
                JSR GetSCBX                   ; need this as SetSCBX trashes A
                CMP #170      
                BCC .checkDrop                ; < 160
                ; End of bomber run (bomber off rigth edge of screen)
                JSR ResetObject
                BRA .end                 

.isDying        CMP #OSTATE_DYING
                BNE .end
                ; TODO - Do bomber dying stuff here
                JSR ResetObject
                BRA .end

.checkDrop      ; A should be object X value
                CMP #80
                BNE .end
                ; Drop bomb (if X = 80, ie: over base)
                STA param1                    ; param1 = 80
                PUSHSCBPTR
                JSR AddNewBomb                ; changes scbPtr
                POPSCBPTR
.end
                RTS

; Apply bomb behaviour to the current object/SCB
UpdateBomb::
                ; Falling
                JSR MoveObjectY
                ; Is Y = 90?
                JSR GetSCBY                   ; need this as SetSCBX trashes A
                CMP #95     
                BNE .end

.bombHit        ; Bomb has hit the base, explode base
                LDA #5
                STA troopersAtBase 
                JSR ResetObject
                BRA .end
.end
                RTS


; Apply fragment behaviour to the current object/SCB
UpdateFragment::
                ; Fragment "state" = OSTATE_LEFT or OSTATE_RIGHT
                ; Fragment "frame" = where we are in the DX/DY table
                ; Fragment has a timeout
                ; Fragment can collide and thus terminate
                ; 1. Check timeout
                LDY #fieldCounter
                LDA (scbPtr),Y
                BEQ .killFragment                       ; counter ran out, so kill fragment
                ; 2. Check collision result
                LDY #scbFieldCollRes
                LDA (scbPtr),Y
                BNE .killNearest                       ; fragment collided with something, so kill it                
                ; Update "frame" (fragment dx/dy table offset)
                LDY #fieldFrame
                LDA (scbPtr),Y
                INC
                STA (scbPtr),Y
                CMP #60      
                BEQ .killFragment                       ; path data ran out, so kill fragment
                DEC
                STA temp                                ; path data index
                ; Update fragment X pos from dx table
                LDY #fieldState                         ; left or right movement?
                LDA (scbPtr),Y
                CMP #OSTATE_LEFT
                BNE .goRight
                ; Going left
                LDY temp
                LDA fragDXTable, Y
                ; Negate DX table value
                EOR #$FF                        ; negate A
                CLC
                ADC #$01                        ; not sure what this is for
                JSR SetSCBDX
                JSR MoveObjectX
                BRA .moveY
.goRight
                ; Going right
                LDY temp
                LDA fragDXTable, Y
                JSR SetSCBDX
                JSR MoveObjectX
.moveY
                ; Update fragment Y from DY table
                LDY temp
                LDA fragDYTable, Y
                JSR SetSCBDY
                JSR MoveObjectY
                ; Animate fragment sprite
                LDA temp
                ROR
                AND #3
                ASL
                TAY
                LDA fragSprPtrs, Y
                LDX fragSprPtrs+1, Y
                JSR SetSCBImage                
                BRA .end

.killNearest    ;STA param1                        ; other object collision id
                JSR ProcessParaHit                 ; kill the nearest object with collision id = param1
 
.killFragment
                JSR ResetObject                   ; kill bullet, set skip flag
.end
                RTS

; Fragment dx table - must handle heli fragments, and base explode fragments
; 1st 20 entries only used for base explosion (upwards movement)
; heli fragments entries start at offset 20 + rnd(8)
fragDXTable     dc.b  2,  1,  2,  1,  1,  2,  1,  1,  1,  1      ; base frags only 
                dc.b  2,  1,  1,  1,  1,  1,  0,  1,  1,  1      ; base frags + heli frags
                dc.b  1,  0,  1,  1,  1,  0,  1,  1,  1,  0      ; 
                dc.b  1,  1,  0,  1,  1,  0,  1,  0,  1,  0
                dc.b  1,  0,  1,  0,  0,  1,  0,  0,  1,  0
                dc.b  0,  1,  0,  0,  1,  0,  0,  0,  1,  0
                dc.b  0,  0,  1,  0,  0,  0,  1,  0,  0,  0
; Fragment dy table
fragDYTable     dc.b -3, -2, -3, -2, -2, -2, -1, -2, -1, -2
                dc.b -1, -1, -1,  0, -1, -1,  0, -1,  0,  0
                dc.b -1, -1,  0, -1,  0, -1,  0,  0,  0,  0
                dc.b  0,  1,  0,  0,  1,  0,  0,  1,  0,  1
                dc.b  0,  1,  1,  1,  1,  1,  1,  2,  1,  1
                dc.b  1,  2,  1,  1,  2,  1,  1,  2,  1,  2
                dc.b  1,  2,  1,  2,  2,  1,  2,  2,  1,  2


; Apply player bullet behaviour to the current object/SCB
UpdatePlayerBullet::
                ; Bullet "state" is ignored (only 1 state)
                ; Bullet has a timeout (for going off screen)
                ; Bullet can also be terminated if collresult != 0
                ; 1. Check timeout
                LDY #fieldCounter
                LDA (scbPtr),Y
                BEQ .killBullet                   ; counter ran out, so kill bullet
                ; 2. Check collision result
                LDY #scbFieldCollRes
                LDA (scbPtr),Y
                BNE .bulletCollided               ; bullet collided with something, so kill it                
                ; Update bullet X position
                JSR MoveObjectX
                ; Update bullet Y position
                JSR MoveObjectY
                BRA .end

.bulletCollided PHA                               ; Save collision result
                JSR GetSCBX                       ; Get current object x and y pos into param1
                STA param1
                JSR GetSCBY
                STA param1 + 1
                PLA                               ; Restore collision result
                CMP #COLID_HELI
                BNE .checkParaHit
                JSR ProcessHeliHit                ; Process bullet hit on helicopter
                BRA .killBullet
.checkParaHit   CMP #COLID_PARA
                BNE .checkBomberHit
                JSR ProcessParaHit                ; Process bullet hit on paratrooper
                BRA .killBullet
.checkBomberHit CMP #COLID_BOMBER
                BNE .checkBomb
                JSR ProcessBomberHit              ; Process bullet hit on bomber
                BRA .killBullet
.checkBomb      CMP #COLID_BOMB
                BNE .killBullet
                JSR ProcessBombHit                ; Process bullet hit on bomb
                ;BRA .killBullet
.killBullet
                JSR ResetObject                   ; kill bullet, set skip flag
.end
                RTS

; Process a possible hit to a helicopter
; In: param1 = bullet x and y pos
; Out: temp = index of object (heli) hit 
ProcessHeliHit::
                PUSHSCBPTR           ; So we can restore scbPtr to "this" object (bullet) when we are finished
                ; Loop thru all objects
                STZ temp
.0              LDA temp
                JSR SetSCBPointer               ; select object A
                ; Correct object type?
                LDY #fieldType
                LDA (scbPtr),Y
                CMP #OTYPE_HELI
                BNE .next
                ; Is heli hit on correct vertical level? heli = 28 * 10 pixels
                LDY #scbFieldY
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1 + 1                   ; our bullet's Y
                BCS .positive
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive       CMP #7                          ; A < 7 ?
                BCS .next                       ; No
                ; Is in correct X range?
                LDY #scbFieldX
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1                      ; our bullet's X
                BCS .positive2
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive2      CMP #16                         ; A < 16 ?
                BCS .next                       ; No
                ; Spawn fragments from the heli
                JSR AddFragments                ; MUST restore the current object scbPtr
                ; Kill this object
                JSR ResetObject
                ; Explode sfx
                JSR TriggerExplosionSfx         ; Trashes A, X and Y
                ; Update score (+5)
                LDA #5
                JSR AddScoreBCD                
                BRA .exit

.next           ; Next object
                INC temp
                LDA temp
                CMP #MAX_ENEMIES
                BNE .0                          ; next object
.exit           ; restore scbPtr back to "current" object (bullet)
                POPSCBPTR
                LDA temp                        ; set return value                 
                RTS

; Process a possible hit to a parachuter
; In: param1 = bullet x and y pos
; Out: temp = index of object (parachueter) hit 
ProcessParaHit::
                ; So we can restore scbPtr to "this" object (bullet) when we are finished
                PUSHSCBPTR
                ; Loop thru all objects
                STZ temp
.0              LDA temp
                JSR SetSCBPointer               ; select object A
                ; Correct object type?
                LDY #fieldType
                LDA (scbPtr),Y
                CMP #OTYPE_PARA
                BNE .next
                ; Is para hit on correct vertical level? para = 12 * 13 pixels
                LDX #0                          ; neg flag
                LDY #scbFieldY
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1 + 1                  ; our bullet's Y
                BCS .positive
                LDX #1                          ; bullet Y > para Y
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive       CMP #8                          ; A < 7 ?
                BCS .next                       ; No
                ; Is in correct X range?
                LDY #scbFieldX
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1                      ; our bullet's X
                BCS .positive2
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive2      CMP #10                         ; A < 16 ?
                BCS .next                       ; No
                ; Kill this parachuter, or kill their parachute?
                CPX #1
                BEQ .killPara
                ; Change para state to "falling"
                LDY #fieldState
                LDA #OSTATE_FALLING
                STA (scbPtr),Y
                LDAX fallSpr
                JSR SetSCBImage
                JSR TriggerShriekSfx            ; para "shriek"
                ; Update score (+5)
                LDA #5
                JSR AddScoreBCD
                BRA .exit

.killPara       ; Kill parachuter
                JSR ResetObject
                ; Play relevant sfx
                JSR TriggerParaHitSfx           ; Trashes A, X and Y
                ;JSR TriggerSplatSfx             ; Trashes A, X and Y
                ; Update score (+2)
                LDA #2
                JSR AddScoreBCD
                BRA .exit

.next           ; Next object
                INC temp
                LDA temp
                CMP #MAX_ENEMIES
                BNE .0                          ; next object
.exit           ; restore scbPtr back to "current" object (bullet)
                POPSCBPTR
                LDA temp                        ; set return value                 
                RTS

; Process a possible hit to a bomber
; In: param1 = bullet x and y pos
; Out: temp = index of object (heli) hit 
ProcessBomberHit::
                PUSHSCBPTR           ; So we can restore scbPtr to "this" object (bullet) when we are finished
                ; Loop thru all objects
                STZ temp
.0              LDA temp
                JSR SetSCBPointer               ; select object A
                ; Correct object type?
                LDY #fieldType
                LDA (scbPtr),Y
                CMP #OTYPE_BOMBER
                BNE .next
                ; Is bomber hit on correct vertical level? (bomber = 32 * 9 pixels)
                LDY #scbFieldY
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1 + 1                   ; our bullet's Y
                BCS .positive
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive       CMP #7                          ; A < 7 ?
                BCS .next                       ; No
                ; Is in correct X range?
                LDY #scbFieldX
                LDA (scbPtr),Y
                SEC                             ; we are trying to do ab "abs()" here
                SBC param1                      ; our bullet's X
                BCS .positive2
                EOR #$FF                        ; negate it
                ADC #$01                        ; not sure what this is for
.positive2      CMP #17                         ; A < 16 ?
                BCS .next                       ; No
                ; Spawn fragments from the heli
                JSR AddFragments                ; MUST restore the current object scbPtr
                ; Kill this object
                JSR ResetObject
                ; Explode sfx
                JSR TriggerExplosionSfx         ; Trashes A, X and Y
                ; Update score (+25)
                LDA #25
                JSR AddScoreBCD     
                BRA .exit

.next           ; Next object
                INC temp
                LDA temp
                CMP #MAX_ENEMIES
                BNE .0                          ; next object
.exit           ; restore scbPtr back to "current" object (bullet)
                POPSCBPTR
                LDA temp                        ; set return value                 
                RTS

; Process a bullet hit to a bomb
; In: param1 = bullet x and y pos
; Out: temp = index of object (heli) hit 
ProcessBombHit::
                PUSHSCBPTR           ; So we can restore scbPtr to "this" object (bullet) when we are finished
                ; Loop thru all objects
                STZ temp
.0              LDA temp
                JSR SetSCBPointer               ; select object A
                ; Correct object type?
                LDY #fieldType
                LDA (scbPtr),Y
                CMP #OTYPE_BOMB
                BNE .next
                ; There is only 1 bomb active at a time
                ; Kill this object (bomb)
                JSR ResetObject
                ; Explode sfx
                JSR TriggerExplosionSfx         ; Trashes A, X and Y
                ; Update score (+25)
                LDA #25
                JSR AddScoreBCD
                BRA .exit
.next           ; Next object
                INC temp
                LDA temp
                CMP #MAX_ENEMIES
                BNE .0                          ; next object
.exit           ; restore scbPtr back to "current" object (bullet)
                POPSCBPTR
                LDA temp                        ; set return value                 
                RTS

; Parachuter landed on base
LandedOnBase::
                ; Trigger "player inactive" mode
                LDA landedCountLeft
                ORA #$80                        ; set top bit in landedCountLeft
                STA landedCountLeft  
                RTS

; Update current object's X position using it's DX
; Trashes: A, X, Y
MoveObjectX::
                JSR GetSCBX                   ; AX = SCB X, Y = fieldX
                STA tempW1
                STX tempW1 + 1  
                JSR GetSCBDX                  ; AX = SCB DX, Y = fieldDX
                STA tempW2
                STX tempW2 + 1
                ADDW tempW1, tempW2           ; tempW2 = tempW1 + tempW2
                LDA tempW2
                LDX tempW2 + 1
                JSR SetSCBX                   ; SCB X = AX 
                RTS

; Update current object's Y position using it's DY
; Trashes: A, X, Y
MoveObjectY::
                JSR GetSCBY                   ; AX = SCB Y, Y = fieldY
                STA tempW1
                STX tempW1 + 1  
                JSR GetSCBDY                  ; AX = SCB DX, Y = fieldDY
                STA tempW2
                STX tempW2 + 1
                ADDW tempW1, tempW2           ; tempW2 = tempW1 + tempW2
                LDA tempW2
                LDX tempW2 + 1
                JSR SetSCBY                   ; SCB Y = AX 
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

; Set the sprite skip bit in sprctl1
SkipSprite::
                PHY
                LDY #scbFieldSprctl1      ; NB: must use #
                LDA (scbPtr),Y
                ORA #SPRCTL1_SKIP
                STA (scbPtr),Y
                PLY
                RTS

; Unset the sprite skip bit in sprctl1
UnskipSprite::
                PHY
                LDY #scbFieldSprctl1      ; NB: must use #
                LDA (scbPtr),Y
                AND #($FF - SPRCTL1_SKIP)                   ; REMOVE bit 2 ($04)
                STA (scbPtr),Y
                PLY
                RTS

; JH - Set "next" pointer of current SCB
; In: AX = addr
SetSCBNext::
                PHY
                LDY #scbFieldNext         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                TXA
                INY
                STA (scbPtr),Y
                PLY
                RTS
                
; JH - Set "image" pointer of current SCB
; In: AX = addr
SetSCBImage::
                PHY
                LDY #scbFieldImage         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                TXA
                INY
                STA (scbPtr),Y
                PLY
                RTS

; JH - Get X of current SCB
; Out: AX = X position
; Trashes: Y
GetSCBX::
                LDY #scbFieldX + 1         ; NB: must use # even though scbFieldX is an equ !
                LDA (scbPtr),Y
                TAX
                DEY
                LDA (scbPtr),Y
                RTS

; JH - Set X of current SCB
; In: AX = X position
; Trashes: Y
SetSCBX::
                LDY #scbFieldX         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                INY
                TXA
                STA (scbPtr),Y
                RTS

; JH - Get Y of current SCB
; Out: AX = Y position
; Trashes: Y
GetSCBY::
                LDY #scbFieldY + 1         ; NB: must use # even though scbFieldX is an equ !
                LDA (scbPtr),Y
                TAX
                DEY
                LDA (scbPtr),Y
                RTS

; JH - Set Y of current SCB
; In: AX = Y position
; Trashes: Y
SetSCBY::
                LDY #scbFieldY         ; NB: must use # even though scbFieldX is an equ !
                STA (scbPtr),Y
                INY
                TXA
                STA (scbPtr),Y
                RTS

; JH - Get DX of current SCB
; Out: AX = SCB DX (word extended)
GetSCBDX::
                LDX #$00                      ; init word extend (MSB) to 0
                LDY #fieldDX
                LDA (scbPtr), y
                BPL .end
                ; If negative, word extend as negative
                LDX #$FF
.end
                RTS

; JH - Set DX of current SCB
; In: A = SCB DX
SetSCBDX::
                LDY #fieldDX         ; NB: must use # even though scbFieldDX is an equ !
                STA (scbPtr),Y
                RTS

; JH - Get DY of current SCB
; Out: AX = SCB DY   (word extended)
GetSCBDY::
                LDX #$00                      ; init word extend (MSB) to 0
                LDY #fieldDY
                LDA (scbPtr), y
                BPL .end
                ; If negative, word extend as negative
                LDX #$FF
.end
                RTS

; JH - Set DY of current SCB
; In: A = SCB DY
SetSCBDY::
                LDY #fieldDY         ; NB: must use # even though scbFieldDY is an equ !
                STA (scbPtr),Y
                RTS

; JH - SCBs for object engine (with embedded object data)
                ALIGN 256
SCBTable        REPT MAX_ENEMIES
                  dc.b SPRCTL0_16_COL | SPRCTL0_NORMAL        ; SPRCTL0
                  dc.b SPRCTL1_LITERAL | SPRCTL1_DEPTH_SIZE_RELOAD              ; SPRCTL1
                  dc.b SPRCOLL_DONT_COLLIDE                   ; SPRCOLL
                  dc.w 0                                      ; pointer to next scb start
                  dc.w heli1Spr                                 ; pointer to sprite image data
                  dc.w 0                                      ; Sprite X
                  dc.w 0                                      ; Sprite Y
                  dc.w $100                                   ; Sprite X scaling
                  dc.w $100                                   ; Sprite Y scaling
                  dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF        ; Palette mapping
                  dc.b 0                                      ; Collision result (offset 23)
                  dc.b 0                                      ; Game object "type" (offset 24)
                  dc.b 0                                      ; Game object "state" (offset 25)
                  dc.b 0                                      ; Game object "DX" (offset 26)
                  dc.b 0                                      ; Game object "DY" (offset 27)
                  dc.b 0                                      ; Game object "frame" (offset 28)
                  dc.b 0                                      ; Game object "counter" (offset 29)
                  ds 2                                        ; padding/reserved to 32 bytes
                ENDR
                REPT MAX_BULLETS
                  dc.b SPRCTL0_16_COL | SPRCTL0_NORMAL        ; SPRCTL0
                  dc.b SPRCTL1_LITERAL | SPRCTL1_DEPTH_SIZE_RELOAD              ; SPRCTL1
                  dc.b SPRCOLL_DONT_COLLIDE                   ; SPRCOLL
                  dc.w 0                                      ; pointer to next scb start
                  dc.w bulletSpr                                 ; pointer to sprite image data
                  dc.w 0                                      ; Sprite X
                  dc.w 0                                      ; Sprite Y
                  dc.w $100                                   ; Sprite X scaling
                  dc.w $100                                   ; Sprite Y scaling
                  dc.b $01,$23,$45,$67,$89,$AB,$CD,$EF        ; Palette mapping
                  dc.b 0                                      ; Collision result (offset 23)
                  dc.b 0                                      ; Game object "type" (offset 24)
                  dc.b 0                                      ; Game object "state" (offset 25)
                  dc.b 0                                      ; Game object "DX" (offset 26)
                  dc.b 0                                      ; Game object "DY" (offset 27)
                  dc.b 0                                      ; Game object "frame" (offset 28)
                  dc.b 0                                      ; Game object "counter" (offset 29)
                  ds 2                                        ; padding/reserved to 32 bytes
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
