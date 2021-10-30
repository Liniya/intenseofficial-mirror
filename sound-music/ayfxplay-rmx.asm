;-Minimal ayFX player v0.15 06.05.06---------------------------;
; original by Shiru                                            ;
; remixed by Hikaru/Intense in 2017, ver 0.1                   ;
;                                                              ;
; A player for sound effects authored with Shiru's AyFxEdit.   ;
; For newly-added effects, an inactive channel is used         ;
; if available, otherwise a channel with the longest current   ;
; duration of playback is used instead.                        ;
; The playback routine uses registers AF,BC,DE,HL.             ;
; This version tests the availability of channels              ;
; in the order B,C,A.                                          ;
;                                                              ;
; Init:                                                        ;
;   ld hl, effect bank address                                 ;
;   call AFXINIT                                               ;
;                                                              ;
; Adding a new effect:                                         ;
;   ld a, effect number [0;254]                                ;
;   call AFXPLAY                                               ;
;                                                              ;
; Once per interrupt:                                          ;
;   call AFXFRAME                                              ;
;                                                              ;
;--------------------------------------------------------------;


; channel descriptors, 4 bytes per channel:
; +0 (2) big endian; pointer to the current frame in effect data
;        a channel is considered free if pointer MSB = 0
; +2 (2) channel playing duration, frames
; ...

afxChDesc	DS 3*4




;--------------------------------------------------------------;
; Initializes the player.                                      ;
; Mutes the AY and sets up variables/buffers.                  ;
; Input: HL = effect bank address                              ;
;--------------------------------------------------------------;

AFXINIT
	inc hl
	ld (afxBnkAdr+1),hl	;save the effect bank address
	ld hl,afxChDesc		;mark all channels as empty
	ld b,3*4
	xor a
afxInit0
	ld (hl),a
	inc hl
	djnz afxInit0
	ld e,14			;zero AY channels 0~13
afxInit1
	dec e
	ld bc,#FFFD
	out (c),e
	ld b,#BF
	out (c),a
	jr nz,afxInit1
	dec a			;mixer = 255 (everything muted)
	ld (afxMixer+1),a
	ret



;--------------------------------------------------------------;
; Main effect playback routine. Must be called each interrupt. ;
; Input: none                                                  ;
;--------------------------------------------------------------;

AFXFRAME
	ld hl,afxChDesc
	ld bc,#03FD

afxFrame0
	ld a,(hl)
	or a
	ld de,4
	jr z,afxFrame6		;if effect pointer MSB == 0, skip the channel
	push hl
	inc hl
	ld l,(hl)
	ld h,a

	ld a,11
	sub b			;select an AY volume register based on channel number
	ld d,b			;(11-3=8, 11-2=9, 11-1=10)

	ld b,#FF		;OUTput the volume
	out (c),a
	ld e,(hl)		;fetch the frame descriptor byte
	inc hl
	ld a,e
	and #0F
	ld b,#BF
	out (c),a

	bit 5,e			;does the tone pitch change?
	jr z,afxFrame1		;if not, skip this part

	ld a,3			;select an AY tone pitch register based on ch. number
	sub d			;3-3=0, 3-2=1, 3-1=2
	add a,a			;0*2=0, 1*2=2, 2*2=4
	ld b,#FF		;OUTput the tone pitch
	out (c),a
	ld b,#BF
	outi
	inc a
	ld b,#FF
	out (c),a
	ld b,#BF
	outi

afxFrame1
	bit 6,e			;does the noise pitch change?
	jr z,afxFrame3		;if not, skip this part
	ld a,(hl)		;fetch new noise pitch value
	sub #20			;check for the end-of-frame sequence
	jr nc,afxFrame2		;if end of frame, set effect ptr MSB to 0 (mark channel as inactive)
	ld a,6
	ld b,#FF		;OUTput the noise pitch
	out (c),a
	ld b,#BF
	outi
	ld a,h
afxFrame2
	ld h,a

afxFrame3
	ld a,e
	ld e,%10010000
	ld b,d			;switch tone/noise bits in the AY mixer register on/off
	inc b			;based on the frame descriptor byte
afxFrame4
	rrc e
	rrca
	djnz afxFrame4
afxMixer
	ld b,#FF
	xor b
	and e
	xor b
	ld (afxMixer+1),a
	ld e,7
	ld b,#FF		;OUTput the AY mixer value
	out (c),e
	ld b,#BF
	out (c),a

	ld b,d
	ex de,hl
	pop hl
	ld (hl),d		;save the new effect pointer value
	inc hl
	ld (hl),e
	inc hl
	inc (hl)		;increase the channel playing duration by 1
	inc hl
	jr nz,afxFrame5
	inc (hl)
afxFrame5
	inc hl
	DEFB #FE
afxFrame6
	add hl,de		;go for the next channel
	djnz afxFrame0
	ret


;--------------------------------------------------------------;
; Sets a new effect to play on an inactive channel.            ;
; If all channels are active, a channel with the longest       ;
; playback duration is selected instead.                       ;
; The availability of channels is tested in the order B,C,A.   ;
; Input: A = effect code [0;254]                               ;
;--------------------------------------------------------------;

AFXPLAY
	ld l,a
	ld h,0
	ld e,h
	ld d,h
	add hl,hl
afxBnkAdr
	ld bc,0			;BC = effect offset table in the effect bank
	add hl,bc
	ld c,(hl)
	inc hl
	ld b,(hl)
	add hl,bc		;HL = effect address
	push hl			;save it on the stack

	ld hl,afxChDesc+4	;scan channel descriptors for an available channel
	ld b,-2
afxPlay0
	ld a,(hl)
	inc hl
	inc hl
	or a
	ld a,(hl)
	inc hl
	jr z,afxPlay2		;if an inactive channel is found, just use that
	cp e
	jr c,afxPlay1		;else look for a channel with the longest playback duration
	ld c,a
	ld a,(hl)
	cp d
	jr c,afxPlay1
	ld e,c
	ld d,a
	push hl
	pop ix
afxPlay1
	inc hl
	inc b
	jp m,afxPlay0
	ld hl,afxChDesc
	jr z,afxPlay0
	push ix
	pop hl
afxPlay2
	pop de
	xor a
	ld (hl),a		;channel playback duration is zeroed
	dec hl
	ld (hl),a
	dec hl
	ld (hl),e		;save the address of data for this effect
	dec hl
	ld (hl),d
	ret