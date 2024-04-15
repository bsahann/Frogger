IDEAL
P386
MODEL FLAT, C
ASSUME cs:_TEXT,ds:FLAT,es:FLAT,fs:FLAT,gs:FLAT

;  Imports
INCLUDE "keyb.inc" ; keyboard handler

; -------------------------------------------------------------------
; MACROS
; -------------------------------------------------------------------

; Video 
VMEMADR EQU 0A0000h	; video memory address
SCRWIDTH EQU 320	; screen width
SCRHEIGHT EQU 200	; screen height
SCRSIZE EQU SCRHEIGHT*SCRWIDTH 
RIGHTBORDER EQU 304
LEFTBORDER EQU 0
TOPBORDER EQU 184
BOTTOMBORDER EQU 12


; Frog drawing
FROGWIDTH EQU 16 	
FROGHEIGHT EQU 16
FROGWIDTHHALF EQU 8
FROGHEIGHTHALF EQU 8
FROGSIZE EQU FROGHEIGHT*FROGWIDTH
FROGJUMP EQU 4


OBSTACLE_SPEED_FACTOR EQU 1
RESPAWN_FROG_X EQU 160
RESPAWN_FROG_Y EQU 184
; Car
CAR_X EQU 10
CAR_Y EQU 156
CARWIDTH EQU 16 	
CARHEIGHT EQU 16
CARSIZE EQU CARWIDTH*CARHEIGHT
ITS_A_CAR EQU 0
;log
LOG_X EQU 50
LOG_Y EQU 50
LOGWIDTH EQU 100
LOGHEIGHT EQU 32
LOGSIZE EQU LOGWIDTH*LOGHEIGHT
ITS_A_LOG EQU 1
;water
WATERBOTTOMBORDER EQU 90
WATERTOPBORDER EQU 22
;road
ROADTOPBORDER EQU 114
;direction of obstacles
LEFT_TO_RIGHT EQU 0
RIGHT_TO_LEFT EQU 1



; Text position
SCORE_X EQU 72;1Fh
SCORE_Y EQU 0;00h
SCORE_END_X EQU 13h
SCORE_END_Y EQU 0Bh
MAINMENU_STR_X EQU 0Ch
MAINMENU_STR_Y EQU 11h

; to do: timer, menu, moving obstacles
; ...

; -------------------------------------------------------------------
; CODE
; -------------------------------------------------------------------

CODESEG		

; Structs
STRUC frog_s
	x dd RESPAWN_FROG_X
	y dd RESPAWN_FROG_Y
	width dd 8
	height dd 8
ENDS frog_s
STRUC car_s
	x dd CAR_X
	y dd CAR_Y
	width dd 14
	height dd 10
ENDS car_s
STRUC log_s
	x dd LOG_X
	y dd LOG_Y
	width dd 70
	height dd 16
ENDS log_s

; ---------- GRAPHICS PROCEDURES ----------

; Setting Video Mode 
PROC set_video_mode
    ARG @@video_mode:byte
    USES eax

    movzx ax, [@@video_mode]
    int 10h

	ret
ENDP set_video_mode

; Refreshing Video
PROC refresh_video
	USES ecx, edi, esi

	cld
	mov esi, offset buffer
	mov edi, VMEMADR
	mov ecx, SCRSIZE  
	rep movsb

	ret
ENDP refresh_video

; Filling the background with one color
PROC fill_background
	ARG 	@@fillcolor:byte
	USES 	eax, ecx, edi

	; Initialize video memory address.
	mov	edi, VMEMADR
	
	; copy color value across all bytes of eax
	mov al, [@@fillcolor]	; ???B
	mov ah, al				; ??BB
	mov cx, ax			
	shl eax, 16				; BB00
	mov ax, cx				; BBBB

	; Scan the whole video memory and assign the background colour.
	mov	ecx, SCRWIDTH*SCRHEIGHT/4
	rep	stosd ; transfer four bytes from AL to ES:[EDI].

	ret
ENDP fill_background

; Drawing background with bin picture
PROC draw_background
	ARG @@destptr:dword, @@packedframe: dword
	USES eax, ebx, ecx, edi 
	
	mov ebx, [@@packedframe]		; source pointer
	mov edi, [@@destptr]			; destination pointer
	
	mov ecx, SCRSIZE				; amount of pixels in ecx
	@@print_pixel:					
		add ebx,1
		mov	al,[ebx]
		stosb
		loop @@print_pixel
	ret 
ENDP draw_background

; Updating colour palette
PROC update_colour_palette
	ARG	 	@@Ncolours: word, @@palette: dword
	USES 	eax, ecx, edx, esi

	mov esi, [@@palette]	; pointer to source palette
	movzx ecx, [@@Ncolours] ; amount of colors to read (movzx = zero extend)
	
	; multiply ecx by 3 (three color components per color)
	; do it efficiently (2*ecx + ecx)
	mov eax, ecx
	sal eax, 1
	add ecx, eax

	mov dx, 03C8h 	; DAC write port
	xor al, al		; index of first color to change (0)
	out dx, al		; write to IO

	inc dx			; DAC Data port (=03C9H)
	rep outsb		; update all colors

	ret
ENDP update_colour_palette

; Drawing the frog (player)
PROC draw_frog
	ARG @@packedframe:dword, @@x:dword, @@y:dword
	USES eax, ebx, ecx, edx, edi
	call open_file, offset frogfile, offset froghandle
	call read_chunk, FROGSIZE, offset froghandle, offset frogframe
	
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	xor ecx, ecx
	xor edi, edi

	mov ebx, [@@packedframe]	; source pointer -> bin file 
	
	mov eax, [@@y];[frog.y] ; y location 
	xor edx, edx
	mov edx, SCRWIDTH 
	mul edx ; scale y location with frame width length
	add eax, [@@x] ; x location 
	mov edi, offset buffer
	add edi, eax				; destination pointer 
	
	mov ecx, FROGHEIGHT
	@@loopi:
		push ecx
		mov ecx, FROGWIDTH
		@@row:
			mov	al, [ebx] ; index in the colour palette
			cmp al, 3 ; color of the background
			je @@skip
			cmp al, 0 ; color of the background
			je @@skip
			add al, 4 ; zombie frog color
			jmp @@print
			@@skip:
			inc edi
			jmp @@end
			@@print:
			stosb ; store pixel
			@@end:
			add ebx, 1 ; increment
			loop @@row
		mov edx, SCRWIDTH-FROGWIDTH		; move one row down in the video memory
		add edi, edx
		pop ecx
		loop @@loopi
	call close_file,offset froghandle  
	ret 
ENDP draw_frog
;drawing the obstacles
PROC draw_obstacles_car
	ARG @@packedframe:dword, @@x:dword, @@y:dword
	USES eax, ebx, ecx, edx, edi
	call open_file, offset carfile, offset carhandle
	call read_chunk, CARSIZE, offset carhandle, offset carframe

	
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	xor ecx, ecx
	xor edi, edi

	mov ebx, [@@packedframe]	; source pointer -> bin file 
	
	mov eax, [@@y]; ; y location 
	xor edx, edx
	mov edx, SCRWIDTH 
	mul edx ; scale y location with frame width length
	add eax, [@@x] ; x location 
	mov edi, offset buffer
	add edi, eax				; destination pointer 
	
	mov ecx, FROGHEIGHT
	@@loopi:
		push ecx
		mov ecx, FROGWIDTH
		@@row:
			mov	al, [ebx] ; index in the colour palette
			cmp al, 3 ; color of the background
			je @@skip
			cmp al, 0 ; color of the background
			je @@skip
			add al, 4 ; 
			jmp @@print
			@@skip:
			inc edi
			jmp @@end
			@@print:
			stosb ; store pixel
			@@end:
			add ebx, 1 ; increment
			loop @@row
		mov edx, SCRWIDTH-FROGWIDTH		; move one row down in the video memory
		add edi, edx
		pop ecx
		loop @@loopi
	call close_file,offset carhandle 

	
	ret 
ENDP draw_obstacles_car
;drawing the logs
PROC draw_obstacles_log
	ARG @@packedframe:dword, @@x:dword, @@y:dword
	USES eax, ebx, ecx, edx, edi
	call open_file, offset logfile, offset logfile
	call read_chunk, LOGSIZE, offset loghandle, offset logframe
	
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	xor ecx, ecx
	xor edi, edi

	mov ebx, [@@packedframe]	; source pointer -> bin file 
	
	mov eax, [@@y]; ; y location 
	xor edx, edx
	mov edx, SCRWIDTH 
	mul edx ; scale y location with frame width length
	add eax, [@@x] ; x location 
	mov edi, offset buffer
	add edi, eax				; destination pointer 
	
	mov ecx, LOGHEIGHT
	@@loopi:
		push ecx
		mov ecx, LOGWIDTH
		@@row:
			mov	al, [ebx] ; index in the colour palette
			cmp al, 3 ; color of the background
			je @@skip
			cmp al, 0 ; color of the background
			je @@skip
			add al, 4 ; 
			jmp @@print
			@@skip:
			inc edi
			jmp @@end
			@@print:
			stosb ; store pixel
			@@end:
			add ebx, 1 ; increment
			loop @@row
		mov edx, SCRWIDTH-LOGWIDTH		; move one row down in the video memory
		add edi, edx
		pop ecx
		loop @@loopi
	call close_file,offset loghandle 
	
	ret 
ENDP draw_obstacles_log

; Draw frogs in winning positions
PROC draw_winning_frogs
	cmp		[win_position_visited], 1 	; box1 visited ?
	jne 	@@box2
	call 	draw_frog, offset frogframe, 40, 14
	@@box2:
	cmp		[win_position_visited+4], 1 	; box2 visited ?
	jne 	@@box3
	call 	draw_frog, offset frogframe, 122, 14
	@@box3:
	cmp		[win_position_visited+4*2], 1 	; box3 visited ?
	jne 	@@box4
	call 	draw_frog, offset frogframe, 182, 14
	@@box4:
	cmp		[win_position_visited+4*3], 1 	; box4 visited ?
	jne 	@@end
	call 	draw_frog, offset frogframe, 262, 14
	@@end:

	ret
ENDP draw_winning_frogs

; Drawing a rectangle
PROC draw_rectangle
	ARG 	@@x0:word, @@y0:word, @@w:word, @@h:word, @@col: byte
	USES 	eax, ecx, edx, edi ; note: MUL uses edx!

	; Compute the index of the rectangle's top left corner
	movzx eax, [@@y0]
	mov edx, SCRWIDTH
	mul edx
	add	ax, [@@x0]

	; Compute top left corner address
	mov edi, VMEMADR
	add edi, eax
	
	; Plot the top horizontal edge.
	movzx edx, [@@w]	; store width in edx for later reuse
	mov	ecx, edx
	mov	al,[@@col]
	rep stosb
	sub edi, edx		; reset edi to left-top corner
	
	; plot both vertical edges
	movzx ecx,[@@h]
	@@vertLoop:
		mov	[edi],al		; left edge
		mov	[edi+edx-1],al	; right edge
		add	edi, SCRWIDTH
		loop @@vertLoop
	; edi should point at the bottom-left corner now
	sub edi, SCRWIDTH

	; Plot the bottom horizontal edge.
	mov	ecx, edx
	rep stosb
	ret
ENDP draw_rectangle

; Draw text
PROC draw_text
	ARG @@offset:DWORD, @@x:dword, @@y:dword
	USES EAX, EBX, EDX
	
	MOV EDX, [@@y] 		; row in EDX
	MOV EBX, [@@x] 		; column in EBX
	MOV AH, 02H			; set cursor position
	SHL EDX, 08H 		; row in DH (00H is top)
	MOV DL, BL 			; column in DL (00H is left)
	MOV BH, 0 			; page number in BH
	INT 10H 			; raise interrupt
	MOV AH, 09H 		; write string to standard output
	MOV EDX, [@@offset] ; offset of ’$’-terminated string in EDX
	INT 21H 			; raise interrupt
	RET
ENDP draw_text

; Draw int
PROC draw_int
	ARG @@int:dword, @@x:byte, @@y:byte
	USES edi,edx,eax, ebx, ecx
	mov ah,02h	;set cursor position
	mov bh,00h	;page number
	mov dh, [@@y] ;row
	mov dl, [@@x]	;column
	int 10h
	
	mov eax, [@@int]
	mov	ebx, 10		; divider
	xor ecx, ecx	; counter for digits to be printed

	; Store digits on stack
	@@getNextDigit:
	inc	ecx         ; increase digit counter
	xor edx, edx
	div	ebx   		; divide by 10
	push dx			; store remainder on stack
	test eax, eax	; {cmp eax, 0} check whether zero?
	jnz	@@getNextDigit

    ; Write all digits to the standard output
	mov	ah, 2h 		; Function for printing single characters.
	@@printDigits:		
	pop dx
	add	dl,'0'      	; Add 30h => code for a digit in the ASCII table, ...
	int	21h            	; Print the digit to the screen, ...
	loop @@printDigits	; Until digit counter = 0.

	ret
ENDP draw_int
;draw obstacles
PROC draw_moving_obstacles
	ARG @@pointer:dword, @@type:dword,@@direction:dword
	
	cmp [@@type], ITS_A_CAR
	je @@draw_Car
	cmp [@@type], ITS_A_LOG
	je @@draw_Log

	@@draw_Car:
		mov ebx, [@@pointer] ;local pointer to car struc
		call check_border_obstacles,  [@@pointer],ITS_A_CAR
		add [ebx + car_s.x],OBSTACLE_SPEED_FACTOR ;adding to position x to make it move

		call 	draw_obstacles_car, offset carframe, [ebx + car_s.x],[ebx + car_s.y]	
		ret
	@@draw_Log:
		mov ebx, [@@pointer] ;local pointer to car struc
		call check_border_obstacles,  [@@pointer],ITS_A_LOG
		cmp[@@direction],LEFT_TO_RIGHT
		jne @@right_to_left
		@@left_to_right:
			add [ebx + log_s.x],OBSTACLE_SPEED_FACTOR ;adding to position x to make it move
			call 	draw_obstacles_log, offset logframe, [ebx + log_s.x],[ebx + log_s.y]
			ret
		@@right_to_left:
			add [ebx + log_s.x],-OBSTACLE_SPEED_FACTOR ;adding to position x to make it move
			call 	draw_obstacles_log, offset logframe, [ebx + log_s.x],[ebx + log_s.y]
			ret
ENDP draw_moving_obstacles

; Updating game video
PROC video_game
	cmp 	al, 0 	; no key pressed ? jump to end
	je 		@@end
	cmp 	[game_state], 0
	je 		@@draw_menu
	cmp 	[game_state], 1
	je		@@draw_game

	@@draw_menu:
	call 	draw_background, offset buffer, offset bgmframe ; draw menu background
	call 	refresh_video
	call 	draw_text, offset main_menu_str, MAINMENU_STR_X, MAINMENU_STR_Y ; draw menu text
	call 	timer, 2
	jmp 	@@end
		
	@@draw_game:
	call 	draw_background, offset buffer, offset bgframe

	call 	draw_moving_obstacles, offset car_1, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_2, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_3, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_4, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_5, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_6, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_7, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_8, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_9, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_10, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_11, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_12, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_13, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_14, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_15, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_16, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_17, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_18, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_19, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset car_20, ITS_A_CAR, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_1, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_2, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_3, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_4, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_5, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_6, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_7, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_8, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_9, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_10, ITS_A_LOG, LEFT_TO_RIGHT
	call 	draw_moving_obstacles, offset log_11, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_12, ITS_A_LOG, RIGHT_TO_LEFT
	call 	draw_moving_obstacles, offset log_13, ITS_A_LOG, RIGHT_TO_LEFT


	call 	draw_winning_frogs

	call 	draw_frog, offset frogframe, [frog.x], [frog.y]
	
	call 	refresh_video
	call 	draw_text, offset score_str, SCORE_X, SCORE_Y; draw score text
	call 	draw_int, [current_score], SCORE_X+6, SCORE_Y ; draw x position
	; call 	draw_int, [frog.y], SCORE_X-25, SCORE_Y ; draw y position
	call 	timer, 3

	jmp @@end
	; call draw_text, offset main_menu_str, MAINMENU_STR_X, MAINMENU_STR_Y ; draw string

	@@update_video:
	call refresh_video ; update video

	@@end:

	ret
ENDP video_game

; --------- GAME LOGIC PROCEDURES ---------

; Game Logic
PROC logic_game
	cmp 	al, 0 	; no key pressed ?
	je 		@@end

    ; switch to game state logic
	cmp [game_state], 0
	je @@menu_logic
	cmp [game_state], 1
	je @@game_logic

	@@menu_logic:
	cmp 	al, 1Ch ; enter key pressed
    jne     @@end 
	mov 	[game_state], 1 ; switch to game state
	call 	update_colour_palette, 80 , offset palette ; switch to game palette
	jmp     @@end 

	@@game_logic:
	cmp     al, 48h 		; UP key pressed ?
	je      @@move_up	
	cmp     al, 4Bh			; LEFT key pressed ?	
	je      @@move_left
	cmp     al, 4Dh			; RIGHT key pressed ?
	je      @@move_right
	cmp     al, 50h			; DOWN key pressed ?
	je      @@move_down

	jmp 	@@check_validity_new_position

		@@move_up:
		add 	[frog.y], -FROGJUMP
		jmp 	@@check_validity_new_position

		@@move_left:
		add 	[frog.x], -FROGJUMP
		jmp 	@@check_validity_new_position

		@@move_right:
		add 	[frog.x],FROGJUMP
		jmp 	@@check_validity_new_position

		@@move_down:
		add 	[frog.y], FROGJUMP
		jmp 	@@check_validity_new_position

	@@check_validity_new_position:
	call check_border
	call check_win ; left to do
	cmp [frog.y], WATERBOTTOMBORDER;check if on water area or road area
	jl @@water_area
	call check_collision, offset car_1 
	call check_collision, offset car_2
	call check_collision, offset car_3
	call check_collision, offset car_4
	call check_collision, offset car_5
	call check_collision, offset car_6
	call check_collision, offset car_7
	call check_collision, offset car_8
	call check_collision, offset car_9
	call check_collision, offset car_10
	call check_collision, offset car_11
	call check_collision, offset car_12
	call check_collision, offset car_13
	call check_collision, offset car_14
	call check_collision, offset car_15
	call check_collision, offset car_16
	call check_collision, offset car_17
	call check_collision, offset car_18
	call check_collision, offset car_19
	call check_collision, offset car_20

	jmp @@end
	

	@@water_area:
		;check if frog on top of any log
		mov [on_log_yes_or_no],0
		call check_if_on_water_or_log, offset log_1
		call check_if_on_water_or_log, offset log_2
		call check_if_on_water_or_log, offset log_3
		call check_if_on_water_or_log, offset log_4
		call check_if_on_water_or_log, offset log_5
		call check_if_on_water_or_log, offset log_6
		call check_if_on_water_or_log, offset log_7
		call check_if_on_water_or_log, offset log_8
		call check_if_on_water_or_log, offset log_9
		call check_if_on_water_or_log, offset log_10
		call check_if_on_water_or_log, offset log_11
		call check_if_on_water_or_log, offset log_12
		call check_if_on_water_or_log, offset log_13

		;on_log_yes_or_no=1 means frog is on top of a log so frog should stay alive
		;on_log_yes_or_no=0 means frog is not top of a log so frog should die
		cmp [on_log_yes_or_no],1
		je @@end
		mov [frog.x], RESPAWN_FROG_X
		mov [frog.y], RESPAWN_FROG_X
		mov [on_log_yes_or_no],0



	@@end:

	ret
ENDP logic_game

; Check validity of new frog position
PROC check_collision
;Collision detection rectangle: 
;if(obstacle.x+obstacle.width>=frog.x && obstacle.x<=frog.x+frog.width
;obstacle.y+obstacle.height>=frog.y && obstacle.y<=frog.y+frog.height)
	ARG @@pointer:dword
	mov ebx, [@@pointer]


	mov edx,0
	add edx,[ebx+car_s.x]
	add edx,[ebx+car_s.width]
	cmp edx , [frog.x] 
	jl @@end ;obstacle.x+obstacle.width>=frog.x
	mov edx,0
	add edx,[frog.x]
	add edx,[frog.width]
	cmp edx , [ebx+car_s.x] 
	jl @@end ;obstacle.x<=frog.x+frog.width
	mov edx,0
	add edx,[ebx+car_s.y]
	add edx,[ebx+car_s.height]
	cmp edx , [frog.y] 
	jl @@end ;obstacle.y+obstacle.height>=frog.y
	mov edx,0
	add edx,[frog.y]
	add edx,[frog.height]
	cmp edx , [ebx+car_s.y] 
	jl @@end ;obstacle.y<=frog.y+frog.height
	mov [frog.x], RESPAWN_FROG_X
	mov [frog.y], RESPAWN_FROG_Y


	@@end:
	mov edx,0

	ret
ENDP check_collision

PROC check_if_on_water_or_log
	ARG @@pointer:dword
	mov ebx, [@@pointer]


	mov edx,0
	add edx,FROGWIDTHHALF
	add edx,[frog.x]
	cmp edx , [ebx +log_s.x] 
	jl @@dead ;frog.x+frog.width/2 >=obstacle.x
	mov edx,0
	mov eax,0
	add edx,[frog.x]
	add edx,FROGWIDTHHALF
	add eax,[ebx+log_s.x]
	add eax,[ebx+log_s.width]
	cmp edx , eax
	jg @@dead ;frog.x+width/2<=obstacle.x+obstacle.width
	mov edx,0
	add edx,FROGHEIGHTHALF
	add edx,[frog.y]
	cmp edx , [ebx +log_s.y] 
	jl @@dead ;frog.y+frog.height/2 >=obstacle.y
	mov edx,0
	mov eax,0
	add edx,[frog.y]
	add edx,FROGHEIGHTHALF
	add eax,[ebx+log_s.y]
	add eax,[ebx+log_s.height]
	cmp edx , eax
	jg @@dead ;frog.y+height/2<=obstacle.y+obstacle.height
	mov edx,0
	mov [on_log_yes_or_no],1

	ret
	@@dead:
	mov edx,0
	ret
	@@end:
	ret
ENDP check_if_on_water_or_log
;check border
PROC check_border
	cmp [frog.x], RIGHTBORDER
	jl @@check_left_border
	add [frog.x], -FROGJUMP
	jmp @@check_top_border

	@@check_left_border:
	cmp [frog.x], LEFTBORDER
	jg @@check_top_border
	add [frog.x], FROGJUMP

	@@check_top_border:
	cmp [frog.y], BOTTOMBORDER
	jg @@check_bottom_border
	add [frog.y], FROGJUMP

	@@check_bottom_border:
	cmp [frog.y], TOPBORDER
	jle @@end
	add [frog.y], -FROGJUMP

	@@end:

	ret
ENDP check_border
;check border of obstacles
PROC check_border_obstacles
	ARG @@pointer:dword, @@type:dword
	mov ebx, [@@pointer]
	cmp [@@type], 0
	je @@check_border_car
	cmp [@@type], 1
	je @@check_border_log
	@@check_border_car:
		@@check_right_border_car:
		cmp [ebx + car_s.x], 319
		jl @@check_left_border_car
		mov [ebx + car_s.x], 0
		jmp @@draw_car

		@@check_left_border_car:
		cmp [ebx + car_s.x], 0
		jg @@draw_car
		mov [ebx + car_s.x], 319
		jmp @@draw_car
	@@check_border_log:
		@@check_right_border_log:
		cmp [ebx + log_s.x], 319
		jl @@check_left_border_log
		mov [ebx + log_s.x], 0
		jmp @@draw_log

		@@check_left_border_log:
		cmp [ebx + log_s.x], 0
		jg @@draw_log
		mov [ebx + log_s.x], 319
		jmp @@draw_log

	@@draw_car:
	call 	draw_obstacles_car, offset carframe, [ebx + car_s.x],[ebx + car_s.y]
	ret
	@@draw_log:
	call 	draw_obstacles_log, offset logframe, [ebx + log_s.x],[ebx + log_s.y]		
	ret
ENDP check_border_obstacles

; Check if frog in winning position and update score
PROC check_win
	@@box1:
	cmp [win_position_visited], 1 	; pass if box was already been visited
	je	@@box2
	mov edx,0
	add edx,FROGWIDTHHALF
	add edx,[frog.x]
	cmp edx , 40; check x postion for win
	jl @@box2 
	mov edx,0
	mov eax,0
	add edx,[frog.x]
	add edx,FROGWIDTHHALF
	add eax,40; check x postion for win
	add eax,FROGWIDTH
	cmp edx , eax
	jg @@box2 
	mov edx,0
	add edx,FROGHEIGHTHALF
	add edx,[frog.y]
	cmp edx , 10 ; check y postion for win
	jl @@box2 
	mov edx,0
	mov eax,0
	add edx,[frog.y]
	add edx,FROGHEIGHTHALF
	add eax,10 ; check y postion for win
	add eax,FROGHEIGHT
	cmp edx , eax
	jg @@box2
	mov [win_position_visited], 1	; set box to visited if in box1 (40,14) location
	add [current_score], 1			; update score if win
	mov [frog.x], RESPAWN_FROG_X
	mov [frog.y], RESPAWN_FROG_Y

	@@box2:
	cmp [win_position_visited+4], 1 	; pass if box was already been visited
	je	@@box3
	mov edx,0
	add edx,FROGWIDTHHALF
	add edx,[frog.x]
	cmp edx , 120; check x postion for win
	jl @@box3
	mov edx,0
	mov eax,0
	add edx,[frog.x]
	add edx,FROGWIDTHHALF
	add eax,120; check x postion for win
	add eax,FROGWIDTH
	cmp edx , eax
	jg @@box3 
	mov edx,0
	add edx,FROGHEIGHTHALF
	add edx,[frog.y]
	cmp edx , 10 ; check y postion for win
	jl @@box3
	mov edx,0
	mov eax,0
	add edx,[frog.y]
	add edx,FROGHEIGHTHALF
	add eax,10 ; check y postion for win
	add eax,FROGHEIGHT
	cmp edx , eax
	jg @@box3
	mov [win_position_visited+4], 1	; set box to visited if in box1 (x,y) location
	add [current_score], 1			; update score if win
	mov [frog.x], RESPAWN_FROG_X
	mov [frog.y], RESPAWN_FROG_Y

	@@box3:
	cmp [win_position_visited+4*2], 1 	; pass if box was already been visited
	je	@@box4
	mov edx,0
	add edx,FROGWIDTHHALF
	add edx,[frog.x]
	cmp edx , 184; check x postion for win
	jl @@box4
	mov edx,0
	mov eax,0
	add edx,[frog.x]
	add edx,FROGWIDTHHALF
	add eax,184; check x postion for win
	add eax,FROGWIDTH
	cmp edx , eax
	jg @@box4 
	mov edx,0
	add edx,FROGHEIGHTHALF
	add edx,[frog.y]
	cmp edx , 10 ; check y postion for win
	jl @@box4
	mov edx,0
	mov eax,0
	add edx,[frog.y]
	add edx,FROGHEIGHTHALF
	add eax,10 ; check y postion for win
	add eax,FROGHEIGHT
	cmp edx , eax
	jg @@box4
	mov [win_position_visited+4*2], 1	; set box to visited if in box1 (x,y) location
	add [current_score], 1			; update score if win
	mov [frog.x], RESPAWN_FROG_X
	mov [frog.y], RESPAWN_FROG_Y

	@@box4:
	cmp [win_position_visited+4*3], 1 	; pass if box was already been visited
	je	@@check_win_and_reset_box
	mov edx,0
	add edx,FROGWIDTHHALF
	add edx,[frog.x]
	cmp edx , 264; check x postion for win
	jl @@check_win_and_reset_box
	mov edx,0
	mov eax,0
	add edx,[frog.x]
	add edx,FROGWIDTHHALF
	add eax,264; check x postion for win
	add eax,FROGWIDTH
	cmp edx , eax
	jg @@check_win_and_reset_box 
	mov edx,0
	add edx,FROGHEIGHTHALF
	add edx,[frog.y]
	cmp edx , 10 ; check y postion for win
	jl @@check_win_and_reset_box
	mov edx,0
	mov eax,0
	add edx,[frog.y]
	add edx,FROGHEIGHTHALF
	add eax,10 ; check y postion for win
	add eax,FROGHEIGHT
	cmp edx , eax
	jg @@check_win_and_reset_box
	mov [win_position_visited+4*3], 1	; set box to visited if in box1 (x,y) location
	add [current_score], 1			; update score if win
	mov [frog.x], RESPAWN_FROG_X
	mov [frog.y], RESPAWN_FROG_Y
	@@check_win_and_reset_box:
	cmp [win_position_visited], 1
	jne @@end
	cmp [win_position_visited+4], 1 
	jne @@end
	cmp [win_position_visited+4*2], 1
	jne @@end
	cmp [win_position_visited+4*3], 1 
	jne @@end
	mov [win_position_visited], 0
	mov [win_position_visited+4], 0
	mov [win_position_visited+4*2], 0
	mov [win_position_visited+4*3], 0
	add [OBSTACLE_SPEED_FACTOR],2


	@@end:

	ret
ENDP check_win

; ------------ FILE PROCEDURES ------------

; Open File
PROC open_file
	ARG @@filename: dword, @@filehandle: dword
	USES eax, ebx, ecx, edx, esi

	mov al, 0 ; read only
	mov edx, [@@filename]
	mov ah, 3dh
	int 21h
	jnc @@no_error ; carry flag is set if error occurs

	@@error:
		call set_video_mode, 03h
		mov  ah, 09h
		mov  edx, offset openErrorMsg
		int  21h

		mov	ah,00h
		int	16h
		call terminate_process
		
	@@no_error:
		mov ebx, [@@filehandle]
		mov esi, [ebx]
		mov [esi], ax
		ret
ENDP open_file

; Read Chunck
PROC read_chunk
	ARG @@size: dword, @@filehandle: dword, @@fileframe: dword
	USES eax, ebx, ecx, edx, esi
	mov ebx, [@@filehandle]
	mov esi, [ebx]
	mov bx, [word esi]
	mov ecx, [@@size]
	mov edx, [@@fileframe]
	mov ah, 3fh
	int 21h
	jnc @@no_error ; carry flag is set if error occurs

	@@error:
		call set_video_mode, 03h
		mov  ah, 09h
		mov  edx, offset readErrorMsg
		int  21h
		
		mov	ah,00h
		int	16h
		call terminate_process
		
	@@no_error:
	ret
ENDP read_chunk

; Close File
PROC close_file
	ARG @@filehandle: dword 
	USES eax, ebx, ecx, edx, esi
	mov ebx, [@@filehandle]
	mov esi, [ebx]
	mov bx, [word esi]
	mov ah, 3Eh
	int 21h
	jnc @@no_error ; carry flag is set if error occurs

	call set_video_mode, 03h
	mov  ah, 09h
	mov  edx, offset closeErrorMsg
	int  21h
	
	@@no_error:
	ret
ENDP close_file

; ------------ OTHER PROCEDURES ------------

; Constant Timer (DANCER ref)
PROC timer
	ARG @@framecount:word
	USES edx,ecx,eax, edi, esi
	
	movzx ecx, [@@framecount]
	mov dx, 03dah ; 
		@@VBlank_phase1:
		in al, dx
		and al, 8
		jnz @@VBlank_phase1
		@@VBlank_phase2:
		in al, dx 
		and al, 8
		jz @@VBlank_phase2
	loop @@VBlank_phase1
	
	ret
ENDP timer

; Reading keyboard input
PROC read_key
	mov 	al, 0
	mov   	al , [__keyb_rawScanCode] ; last pressed key
	cmp     al, 01h ; ESC key pressed ?
	jne 	@@end
	call 	terminate_process

	@@end:
	ret
ENDP read_key
PROC init_frog
	; load frogmain
	call open_file, offset frogfile, offset froghandle
	call read_chunk, FROGSIZE, offset froghandle, offset frogframe
	ret
ENDP init_frog


; Initializing the game
PROC init_game
	call set_video_mode, 13h
	; update color palette
	call update_colour_palette, 80 , offset palette_menu
	; load background menu
	call open_file, offset bgmfile, offset bgmhandle
	call read_chunk, SCRSIZE, offset bgmhandle, offset bgmframe
	; load background game
	call open_file, offset bgfile, offset bghandle
	call read_chunk, SCRSIZE, offset bghandle, offset bgframe
	;call init_frog






	; drawings
	; call draw_background, offset buffer, offset bgmframe

	; call draw_frog, offset frogframe
	; call draw_frog, offset frog_frame
	call refresh_video
		; call displayString, offset main_menu_msg1, MAINMENU_MSG1_X, MAINMENU_MSG1_Y
		; call displayString, offset main_menu_msg2, MAINMENU_MSG2_X, MAINMENU_MSG2_Y
		; call displayString, offset main_menu_msg3, MAINMENU_MSG3_X, MAINMENU_MSG3_Y

	call __keyb_installKeyboardHandler

	mov [game_state], 0 ; menu state
	ret
ENDP init_game

; Stopping the game, back to terminal (text)
PROC terminate_process
	USES eax
	call 	__keyb_uninstallKeyboardHandler
	call 	close_file, offset froghandle
	call 	close_file, offset bghandle
	call 	close_file, offset bgmhandle
	call 	close_file, offset carhandle
	call 	close_file, offset loghandle
	call 	set_video_mode, 03h
	mov		ax,04C00h
	int 	21h
	
	ret
ENDP terminate_process

; Main 
PROC main
	sti
	cld
	
	push ds ; ?
	pop	es  ; ?

	call init_game

	@@game_loop:
	call read_key	; read keyboard input
	call logic_game	; update game state
	call video_game ; update game video
	jmp @@game_loop
		       
ENDP main

; -------------------------------------------------------------------
; UDATASEG
; -------------------------------------------------------------------
UDATASEG		
	bghandle dw ?
	bgmhandle dw ?
	froghandle dw ?
	carhandle dw ?
	loghandle dw ?

	frogframe db 16 dup (?)
	carframe db 16 dup (?)
	logframe db LOGSIZE dup (?)
	bgframe db SCRSIZE dup (?)
	bgmframe db SCRSIZE dup (?)
	buffer db SCRSIZE dup (?)

; -------------------------------------------------------------------
; DATA
; -------------------------------------------------------------------
DATASEG
	
	; game logic variabels
	;starting positions car <x,y>
	frog frog_s 	<,,,,>
	car_1 car_s		<10,113,,>;row1
	car_2 car_s		<90,113,,>
	car_3 car_s		<200,113,,>
	car_4 car_s		<270,113,,>
	car_5 car_s		<30,127,,>;row2
	car_6 car_s		<80,127,,>
	car_7 car_s		<150,127,,>
	car_8 car_s		<250,127,,>
	car_9 car_s		<20,141,,>;row3
	car_10 car_s	<100,141,,>
	car_11 car_s	<210,141,,>
	car_12 car_s	<300,141,,>
	car_13 car_s	<50,155,,>;row4
	car_14 car_s	<120,155,,>
	car_15 car_s	<175,155,,>
	car_16 car_s	<285,155,,>
	car_17 car_s	<10,170,,>;row5
	car_18 car_s	<70,170,,>
	car_19 car_s	<200,170,,>
	car_20 car_s	<270,170,,>


	;starting positions log <x,y>
	log_1 log_s		<50,82,,>
	log_2 log_s		<190,82,,>
	log_3 log_s		<70,70,,>
	log_4 log_s		<210,70,,>
	log_5 log_s		<80,58,,>
	log_6 log_s		<235,58,,>
	log_7 log_s		<60,46,,>
	log_8 log_s		<195,46,,>
	log_9 log_s		<60,34,,>
	log_10 log_s	<175,34,,>
	log_11 log_s	<35,22,,>
	log_12 log_s	<165,22,,>
	log_13 log_s	<245,22,,>


	game_state 		dd 0
	on_log_yes_or_no dd 0
	current_score 	dd 0
	current_lives 	dd 3
	win_position_visited dd 0
		dd 6
		dd 0
		dd 0

	; keyboard last pressed key value
	input_key dd 0

	;Color Palette
	palette	db 7,31,45
		db 1,1,1
		db 14,47,16
		db 63,63,63
		db 0,37,0
		db 20,50,17
		db 0,26,1
		db 9,32,46
		db 15,48,16
		db 18,44,17
		db 63,62,24
		db 63,63,1
		db 34,34,29
		db 4,27,23
		db 37,36,36
		db 3,63,0		;start palette frog
		db 59,59,59
		db 63,63,63
		db 63,60,0
		db 58,0,52
		db 63,10,12 	;start palette car
		db 56,15,63
		db 62,52,0
		db 0,0,0
		db 63,63,63		;start log 
		db 39,21,21
		db 15,15,13



	palette_menu db 13,13,25
		db 14,19,34
		db 13,17,29
		db 58,56,7
		db 24,39,9
		db 55,56,56
		db 37,43,9
		db 21,26,8
		db 12,24,8
		db 21,23,23
		db 36,42,21
		db 41,49,8
		db 41,50,22
		db 44,50,52
		db 13,35,8
		db 27,39,20
		db 38,42,42
		db 39,45,50
		db 53,56,23
		db 9,11,11
		db 19,23,34
		db 59,9,5
		db 53,55,39
		db 44,51,38
		db 59,24,22
		db 27,36,41
		db 57,41,37
		db 60,36,27
		db 50,45,8
		db 35,26,8
		db 38,25,24
		db 60,20,12



	; Files
	bgfile				db "bg4.bin", 0
	bgmfile 			db "bgm.bin", 0
	frogfile			db "frog.bin", 0
	carfile				db "car.bin", 0
	logfile				db "log.bin", 0

    ; Error Messages
	openErrorMsg 	db "could not open file", 13, 10, '$'
	readErrorMsg 	db "could not read data", 13, 10, '$'
	closeErrorMsg 	db "error during file closing", 13, 10, '$'

	; Game Texts
	main_menu_str 	db "Press ENTER to play", 13, 10, '$'
	score_str 		db "Score: 0", 13, 10, '$'

; -------------------------------------------------------------------
; STACK
; -------------------------------------------------------------------
STACK 100h

END main