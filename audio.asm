; JH - Paratroopers game sound
; Modifed from BLL example sound.asm 
;
; SFX needed:
;	- [DONE] Shoot                    ShotSnd
;	- [BUSY] Chute hit
;	- Para hit
;	- [DONE] Heli explosion
;	- [DONE] Base explosion
;	- Trooper landing
;	- Trooper splatting
;	- Trooper marching

SND_TIMER       set 7

; ONe tiem setup of the BLL sound sytem
InitAudio::
                jsr SndInit                           ; Init the BLL sound system (sets up IRQ etc)
                LDAY DefineENVs                       ; Set up the envelopes
                ldx #0
                jsr SndStartSound

                LDAY ShotSnd
                ldx #2
                jsr SndStartSound                     ; Start "Shot" sound on channel 2

                RTS

; Trigger player fire sfx
; Trashes: A, X and Y
TriggerPlayerFireSfx::
                LDAY ShotSnd
                LDX #0
                JSR SndStartSound                     ; Start "Shot" sound on channel 0
                RTS

; Trigger heli explosion sfx
; Trashes: A, X and Y
TriggerExplosionSfx::
                LDAY HeliExplSnd
                LDX #1
                JSR SndStartSound                     ; Start "explode" sound on channel 1
                RTS

; Trigger player explosion sfx
; Trashes: A, X and Y
TriggerPlayerExplosionSfx::
                LDAY PlayerExplSnd
                LDX #0
                JSR SndStartSound                     ; Start "explode" sound on channel 1
                RTS

; Trigger shriek sfx
; Trashes: A, X and Y
TriggerShriekSfx::
                LDAY ShriekSnd
                LDX #2
                JSR SndStartSound                     ; Start "shriek" sound on channel 2
                RTS

; Trigger parachuter hit sfx
; Trashes: A, X and Y
TriggerParaHitSfx::
                LDAY ParaHitSnd
                LDX #2
                JSR SndStartSound                     ; Start "para hit" sound on channel 2
                RTS

; Trigger splat sfx
; Trashes: A, X and Y
TriggerSplatSfx::
                LDAY SplatSnd
                LDX #2
                JSR SndStartSound                     ; Start "splat" sound on channel 2
                RTS

; Trigger trooper move sfx
; Trashes: A, X and Y
TriggerTrooperMoveSfx::
                LDAY TrooperMoveSnd
                LDX #1
                JSR SndStartSound                     ; Start "trooper move" sound on channel 2
                RTS


;		include <includes/sound.inc>
;               include <macros/sound.mac>

; This is actually a "play list" that sets up the envelopes
DefineENVs:
                DEFVOL 15,splatVolEnv
                DEFFRQ 15,splatFreqEnv
                DEFVOL 14,explVolEnv
                DEFFRQ 14,explFreqEnv
                DEFVOL 13,shotVolEnv
                DEFFRQ 13,shotFreqEnv
                DEFVOL 12,playerExplVolEnv
                DEFFRQ 12,playerExplFreqEnv
                DEFVOL 11,gnurbshVolEnv
                DEFFRQ 11,gnurbshFreqEnv
                DEFFRQ 10,ufoenv1
                DEFVOL 9,shriekVolEnv
                DEFFRQ 9,shriekFreqEnv
                dc.b 0

splatVolEnv:    dc.b 0,3,10,-10,2,15,20,-6
splatFreqEnv:   dc.b 1,1,4,-8
explVolEnv:     dc.b 0,1,60,-2
explFreqEnv:    dc.b 1,1,1,-4
playerExplVolEnv:  dc.b 0,1,60,-1
playerExplFreqEnv: dc.b 1,1,1,-2
shotVolEnv:     dc.b 2,2,2,-10,1,-8     ; 2,2,2,-10,1,-8
shotFreqEnv:    dc.b 1,1,4,-15      ; 0,1,40,-15 does nto work!
ufoenv1         dc.b 1,2,20,-2,20,2
gnurbshVolEnv:  dc.b 0,1,20,-10
gnurbshFreqEnv: dc.b 1,1,1,-20
shriekVolEnv:  dc.b 0,1,60,-3
shriekFreqEnv: dc.b 0,2,20,5,40,-5

ShotSnd:
                SETFRQ 13               ;shotenv               ; $8b, 13       (set freq env no)
                SETVOL 13               ;15               ; $88, 13       (set vol env no)
                INSTR 3,120,120                           ; $84,0,0,\0,\1,\2  (set up instrument params)
                PLAY 45,40                                ; freq, length (ticks?)
                STOP                                      ; $83
                dc.b 0                                    ; sound "play list" terminator

HeliExplSnd
                SETVOL 14               ; explodeVolEnv
                SETFRQ 14
                INSTR $ff,120,120
                PLAY 60,60
                STOP
                dc.b 0

AlienMoveSnd
                SETFRQ 11
                SETVOL 11
                INSTR $31,20,20
                PLAY 70,10
                INSTR $30,20,20
                PLAY 70,10
                STOP
                dc.b 0

NotHitExplSnd
                SETFRQ 13               ; shotenv
                SETVOL 13
                INSTR $5,120,120
                PLAY 70,40
                STOP
                dc.b 0


PlayerExplSnd
                SETVOL 12              ; playerExpEnv
                SETFRQ 12
                INSTR $ff,120,120
                PLAY 40,200
                STOP
                dc.b 0

ShriekSnd
                SETVOL 9              ; shreikVolEnv
                SETFRQ 9             ; shriekFreqEnv
                INSTR 3,120,120
                PLAY 50,60
                STOP
                dc.b 0

ParaHitSnd:
                SETFRQ 15               ;splatenv
                SETVOL 15               
                INSTR 5,120,120                           ; $84,0,0,\0,\1,\2  (set up instrument params)
                PLAY 40,20                                ; freq, length (ticks?)
                STOP
                dc.b 0

SplatSnd:
                SETFRQ 15               ;splatenv
                SETVOL 15               
                INSTR 3,120,120                           ; $84,0,0,\0,\1,\2  (set up instrument params)
                PLAY 25,20                                ; freq, length (ticks?)
                STOP
                dc.b 0

TrooperMoveSnd
                SETFRQ 11
                SETVOL 11
                INSTR $31,20,20
                PLAY 70,10
                STOP
                dc.b 0

UfoSnd
;-->                DEFFRQ 10,ufoenv1
                SETFRQ 10
                INSTR $3,50,50
                PLAY 50,1000
                STOP
                dc.b 0
