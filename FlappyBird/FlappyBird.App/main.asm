; ============================================================================
; FlappyBird - x86 Irvine32 Assembly
; ============================================================================
; Assembler: MASM (ml.exe)
; Libraries: Irvine32.lib, kernel32.lib, user32.lib
; ============================================================================

INCLUDE Irvine32.inc

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
SCREEN_W        EQU  80          ; console columns
SCREEN_H        EQU  25          ; console rows
BIRD_COL        EQU  10          ; bird's fixed X column
MAX_PIPES       EQU  10          ; max simultaneous pipes
FRAME_DELAY     EQU  33          ; ~30 FPS (milliseconds)
GROUND_ROW      EQU  23          ; ground starts at row 23 (0-indexed)
PIPE_WIDTH      EQU  5           ; visual width of pipe in columns
VK_SPACE        EQU  20h         ; virtual key code for spacebar

; Pipe struct — 16 bytes each, aligned
Pipe STRUCT
    pX        REAL4  ?           ; horizontal position (float, scrolls left)
    gapY      REAL4  ?           ; top of gap (row, float)
    gapSize   REAL4  ?           ; gap height in rows (float)
    scored    BYTE   ?           ; has this pipe been scored?
    pad       BYTE  3 DUP(?)    ; padding for alignment
Pipe ENDS

; ---------------------------------------------------------------------------
; Data Segment
; ---------------------------------------------------------------------------
.data

; --- Physics State (floats for FPU) ---
birdY           REAL4  10.0      ; bird Y position in rows (starts mid-screen)
birdVelocity    REAL4  0.0       ; vertical velocity
gravity         REAL4  0.18      ; gravity per frame (tuned for console)
jumpStrength    REAL4  -1.05     ; jump impulse (negative = up)

; --- Game State ---
score           DWORD  0
highScore       DWORD  0
gameOver        BYTE   0
playing         BYTE   0
jumpRequested   BYTE   0

; --- Pipe Array ---
pipes           Pipe   MAX_PIPES DUP(<>)
pipeCount       DWORD  0

; --- Timing ---
lastFrameTime   DWORD  0

; --- Rendering constants (floats for FPU comparisons) ---
floorLimit      REAL4  22.0      ; bird can't go below row 22
ceilLimit       REAL4  0.0       ; bird can't go above row 0
pipeSpeed       REAL4  0.8       ; pipe scroll speed per frame
offScreenLeft   REAL4  -6.0      ; pipe is off-screen when pX < this
spawnThreshold  REAL4  55.0      ; spawn new pipe when last pipe < this col
newPipeX        REAL4  80.0      ; new pipes start at right edge
defaultGapSize  REAL4  7.0       ; gap = 7 rows
birdSizeF       REAL4  1.0       ; bird occupies 1 row for collision
pipeWidthF      REAL4  5.0       ; pipe width in columns for collision
birdColF        REAL4  10.0      ; bird column as float
sixtyF          REAL4  60.0      ; for scoring check (pX + pipeWidth < birdX)
zeroF           REAL4  0.0
oneF            REAL4  1.0

; --- Screen Buffer (80 x 25 = 2000 chars + 2000 colors) ---
screenChars     BYTE   2000 DUP(' ')
screenColors    BYTE   2000 DUP(0)

; --- Strings ---
titleStr        BYTE   "FLAPPY BIRD", 0
startStr        BYTE   "Press SPACE to Start", 0
gameOverStr     BYTE   "GAME OVER", 0
restartStr      BYTE   "Press SPACE to Restart", 0
scoreLabel      BYTE   "Score: ", 0
hiScoreLabel    BYTE   "Best: ", 0
separatorStr    BYTE   "---", 0

; --- Temp string buffer for building centered score/best lines ---
tempStrBuf      BYTE   32 DUP(0)

; --- Color Constants ---
; Irvine color format: high nibble = background, low nibble = foreground
skyColor        BYTE   30h      ; cyan background, black foreground
groundColor     BYTE   60h      ; brown background, black foreground  
pipeColor       BYTE   20h      ; green background, black foreground
pipeCapColor    BYTE   0A0h     ; bright green bg, black fg -> use 2Ah
birdColor       BYTE   0Eh     ; black bg, yellow foreground
scoreColor      BYTE   3Fh     ; cyan bg, white fg
hiScoreColor    BYTE   3Eh     ; cyan bg, yellow fg
gameOverColor   BYTE   0Ch     ; black bg, light red fg
titleColor      BYTE   0Eh     ; black bg, yellow fg
menuColor       BYTE   0Fh     ; black bg, white fg
overlayColor    BYTE   08h     ; black bg, dark gray fg

; --- Temp variables for procedures ---
tempInt         DWORD  0
tempInt2        DWORD  0
tempFloat       REAL4  0.0
randRange       DWORD  0

; console cursor info for hiding cursor
cursorInfo      CONSOLE_CURSOR_INFO <>
consoleHandle   DWORD  0

; ---------------------------------------------------------------------------
; Code Segment
; ---------------------------------------------------------------------------
.code

; ===================================================================
; HideCursor - Hide the console cursor for cleaner rendering
; ===================================================================
HideCursor PROC
    pushad
    INVOKE GetStdHandle, STD_OUTPUT_HANDLE
    mov consoleHandle, eax
    
    ; Get current cursor info
    INVOKE GetConsoleCursorInfo, consoleHandle, ADDR cursorInfo
    
    ; Set cursor invisible
    mov cursorInfo.bVisible, FALSE
    INVOKE SetConsoleCursorInfo, consoleHandle, ADDR cursorInfo
    
    popad
    ret
HideCursor ENDP

; ===================================================================
; SetConsoleSize - Set console window title
; ===================================================================
SetTitle PROC
    pushad
    INVOKE SetConsoleTitle, ADDR titleStr
    popad
    ret
SetTitle ENDP

; ===================================================================
; InitGame - Reset all game state, create first pipe
; ===================================================================
InitGame PROC
    pushad
    
    ; Reset bird
    fld defaultGapSize          ; load 7.0
    fld oneF                    ; load 1.0
    fld oneF                    ; stack: 1, 1, 7
    fadd                        ; stack: 2, 7
    fadd                        ; stack: 9
    fadd oneF                   ; stack: 10
    fstp birdY                  ; birdY = 10.0
    
    fldz
    fstp birdVelocity           ; velocity = 0
    
    ; Reset game state
    mov score, 0
    mov gameOver, 0
    mov playing, 0
    mov jumpRequested, 0
    
    ; Clear pipe array
    mov pipeCount, 0
    
    ; Add first pipe at right edge
    ; pipes[0].pX = 80.0
    lea edi, pipes
    fld newPipeX
    fstp (Pipe PTR [edi]).pX
    
    ; pipes[0].gapY = 8.0 (random-ish start)
    ; Generate random gap position: 3 to 16
    mov eax, 14                 ; range = 14
    call RandomRange            ; eax = 0..13
    add eax, 3                  ; eax = 3..16
    mov tempInt, eax
    fild tempInt
    fstp (Pipe PTR [edi]).gapY
    
    ; pipes[0].gapSize = 7.0
    fld defaultGapSize
    fstp (Pipe PTR [edi]).gapSize
    
    ; pipes[0].scored = 0
    mov (Pipe PTR [edi]).scored, 0
    
    mov pipeCount, 1
    
    popad
    ret
InitGame ENDP

; ===================================================================
; UpdatePhysicsAsm - Apply gravity and jump (FPU)
; Directly ported from C++ inline assembly
; ===================================================================
UpdatePhysicsAsm PROC
    ; Check if game is over
    mov al, gameOver
    test al, al
    jnz physics_end
    
    ; Check if playing
    mov al, playing
    test al, al
    jz physics_end
    
    ; Check if jump requested
    mov al, jumpRequested
    test al, al
    jz apply_gravity
    
    ; Apply jump: birdVelocity = jumpStrength
    fld jumpStrength
    fstp birdVelocity
    mov jumpRequested, 0
    
apply_gravity:
    ; birdVelocity += gravity
    fld birdVelocity
    fadd gravity
    fst birdVelocity
    
    ; birdY += birdVelocity
    fadd birdY
    fstp birdY
    
    ; Clamp: if birdY < 0, birdY = 0
    fld birdY
    fcomp ceilLimit
    fstsw ax
    sahf
    ja check_floor              ; if birdY > 0, check floor
    
    fldz
    fstp birdY
    jmp physics_end
    
check_floor:
    ; if birdY >= floorLimit, game over
    fld birdY
    fcomp floorLimit
    fstsw ax
    sahf
    jb physics_end              ; birdY < floor, OK
    
    ; Bird hit the ground
    fld floorLimit
    fstp birdY
    mov gameOver, 1
    
physics_end:
    ret
UpdatePhysicsAsm ENDP

; ===================================================================
; CheckCollisionAsm - Check bird vs one pipe (FPU)
; Parameters: esi = pointer to Pipe struct
; Ported from C++ inline assembly
; ===================================================================
CheckCollisionAsm PROC
    ; Already game over? Skip.
    mov al, gameOver
    test al, al
    jnz coll_end
    
    ; Check horizontal overlap:
    ; if (birdCol + 1 < pipeX) -> no collision (bird is left of pipe)
    fld birdColF
    fadd birdSizeF              ; birdCol + 1
    fcomp (Pipe PTR [esi]).pX
    fstsw ax
    sahf
    jb coll_end                 ; bird right edge < pipe left edge
    
    ; if (pipeX + pipeWidth < birdCol) -> no collision (pipe is left of bird)
    fld (Pipe PTR [esi]).pX
    fadd pipeWidthF
    fcomp birdColF
    fstsw ax
    sahf
    jb coll_end                 ; pipe right edge < bird left edge
    
    ; Horizontal overlap exists — check vertical
    ; if (birdY < gapY) -> hit top pipe
    fld birdY
    fcomp (Pipe PTR [esi]).gapY
    fstsw ax
    sahf
    jb set_gameover             ; birdY < gapY (above gap = in top pipe)
    
    ; if (birdY + birdSize > gapY + gapSize) -> hit bottom pipe
    fld (Pipe PTR [esi]).gapY
    fadd (Pipe PTR [esi]).gapSize
    fld birdY
    fadd birdSizeF
    fcompp
    fstsw ax
    sahf
    ja set_gameover             ; bird bottom > gap bottom
    
    jmp coll_end
    
set_gameover:
    mov gameOver, 1
    ; Update high score
    mov eax, score
    cmp eax, highScore
    jbe coll_end
    mov highScore, eax
    
coll_end:
    ret
CheckCollisionAsm ENDP

; ===================================================================
; ProcessInput - Non-blocking key check using ReadKey
; ===================================================================
ProcessInput PROC
    pushad
    
    call ReadKey                ; Check for keypress (non-blocking)
    jz no_key                  ; ZF set = no key available
    
    ; Check if it's spacebar
    cmp dx, VK_SPACE            ; dx = virtual key code from ReadKey
    jne no_key
    
    ; Space was pressed
    cmp gameOver, 1
    jne not_game_over
    
    ; Game over: restart
    call InitGame
    jmp input_done
    
not_game_over:
    cmp playing, 1
    je already_playing
    
    ; Start playing
    mov playing, 1
    mov jumpRequested, 1
    jmp input_done
    
already_playing:
    ; Jump
    mov jumpRequested, 1
    
input_done:
no_key:
    popad
    ret
ProcessInput ENDP

; ===================================================================
; UpdatePipes - Move pipes left, check scoring, spawn/despawn
; ===================================================================
UpdatePipes PROC
    pushad
    
    ; Only update if playing and not game over
    cmp playing, 1
    jne update_pipes_done
    cmp gameOver, 1
    je update_pipes_done
    
    ; Move all pipes left
    mov ecx, pipeCount
    test ecx, ecx
    jz spawn_check
    
    lea esi, pipes
    xor ebx, ebx                ; index
    
move_loop:
    cmp ebx, pipeCount
    jge remove_check
    
    ; pipes[ebx].pX -= pipeSpeed
    fld (Pipe PTR [esi]).pX
    fsub pipeSpeed
    fstp (Pipe PTR [esi]).pX
    
    ; Check scoring: if !scored && pX + pipeWidth < birdCol
    cmp (Pipe PTR [esi]).scored, 0
    jne no_score
    
    fld (Pipe PTR [esi]).pX
    fadd pipeWidthF
    fcomp birdColF
    fstsw ax
    sahf
    ja no_score                 ; pipe right edge > bird column, not passed yet
    
    ; Score!
    mov (Pipe PTR [esi]).scored, 1
    inc score
    mov eax, score
    cmp eax, highScore
    jbe no_score
    mov highScore, eax
    
no_score:
    ; Check collision for this pipe
    call CheckCollisionAsm      ; esi already points to pipe
    
    add esi, SIZEOF Pipe
    inc ebx
    jmp move_loop
    
remove_check:
    ; Remove pipes that scrolled off-screen (front of array)
    lea esi, pipes
    fld (Pipe PTR [esi]).pX
    fcomp offScreenLeft
    fstsw ax
    sahf
    ja spawn_check              ; first pipe still on screen
    
    ; Shift array left by one
    mov ecx, pipeCount
    dec ecx
    mov pipeCount, ecx
    test ecx, ecx
    jz spawn_check
    
    ; memcpy: move pipes[1..n] to pipes[0..n-1]
    lea edi, pipes
    lea esi, pipes
    add esi, SIZEOF Pipe
    imul ecx, SIZEOF Pipe
    rep movsb
    
spawn_check:
    ; Spawn new pipe if last pipe.pX < spawnThreshold
    mov ecx, pipeCount
    test ecx, ecx
    jz do_spawn                 ; no pipes, spawn one
    
    ; Get last pipe
    dec ecx
    imul ecx, SIZEOF Pipe
    lea esi, pipes
    add esi, ecx
    
    fld (Pipe PTR [esi]).pX
    fcomp spawnThreshold
    fstsw ax
    sahf
    ja update_pipes_done        ; last pipe still far right, don't spawn
    
do_spawn:
    ; Check if we have room
    mov ecx, pipeCount
    cmp ecx, MAX_PIPES
    jge update_pipes_done       ; array full
    
    ; Add new pipe at pipes[pipeCount]
    imul ecx, SIZEOF Pipe
    lea edi, pipes
    add edi, ecx
    
    ; pX = 80.0
    fld newPipeX
    fstp (Pipe PTR [edi]).pX
    
    ; Random gapY: 3 to 16
    mov eax, 14
    call RandomRange            ; eax = 0..13
    add eax, 3
    mov tempInt, eax
    fild tempInt
    fstp (Pipe PTR [edi]).gapY
    
    ; gapSize = 7.0
    fld defaultGapSize
    fstp (Pipe PTR [edi]).gapSize
    
    ; scored = 0
    mov (Pipe PTR [edi]).scored, 0
    
    inc pipeCount
    
update_pipes_done:
    popad
    ret
UpdatePipes ENDP

; ===================================================================
; ClearScreenBuffer - Fill screen buffer with sky color
; ===================================================================
ClearScreenBuffer PROC
    pushad
    
    ; Fill chars with space, colors with sky color
    lea edi, screenChars
    mov ecx, SCREEN_W * SCREEN_H
    mov al, ' '
    rep stosb
    
    lea edi, screenColors
    mov ecx, SCREEN_W * SCREEN_H
    mov al, skyColor
    rep stosb
    
    ; Draw ground (rows 23-24)
    ; Row 23: ground top (dark)
    mov eax, GROUND_ROW
    imul eax, SCREEN_W
    lea edi, screenChars
    add edi, eax
    mov ecx, SCREEN_W
    mov al, 0B2h                ; ▓ character
    rep stosb
    
    lea edi, screenColors
    mov eax, GROUND_ROW
    imul eax, SCREEN_W
    add edi, eax
    mov ecx, SCREEN_W
    mov al, 62h                 ; brown bg, green fg
    rep stosb
    
    ; Row 24: ground bottom
    mov eax, GROUND_ROW
    inc eax
    imul eax, SCREEN_W
    lea edi, screenChars
    add edi, eax
    mov ecx, SCREEN_W
    mov al, 0B1h                ; ░ character  
    rep stosb
    
    lea edi, screenColors
    mov eax, GROUND_ROW
    inc eax
    imul eax, SCREEN_W
    add edi, eax
    mov ecx, SCREEN_W
    mov al, 06Eh                ; brown bg, yellow fg
    rep stosb
    
    popad
    ret
ClearScreenBuffer ENDP

; ===================================================================
; DrawPipesToBuffer - Draw all pipes into the screen buffer
; ===================================================================
DrawPipesToBuffer PROC
    pushad
    
    mov ecx, pipeCount
    test ecx, ecx
    jz draw_pipes_done
    
    lea esi, pipes
    xor ebx, ebx               ; pipe index
    
draw_pipe_loop:
    cmp ebx, pipeCount
    jge draw_pipes_done
    
    ; Convert pipeX to integer column
    fld (Pipe PTR [esi]).pX
    fistp tempInt
    mov eax, tempInt            ; eax = pipe column (int)
    
    ; Convert gapY to integer
    fld (Pipe PTR [esi]).gapY
    fistp tempInt
    mov edx, tempInt            ; edx = gap top row
    
    ; Convert gapSize to integer
    fld (Pipe PTR [esi]).gapSize
    fistp tempInt2
    ; gap bottom row = edx + tempInt2
    
    ; Draw pipe body and caps for each column of the pipe
    push ebx                    ; save pipe index
    
    xor ecx, ecx               ; column offset within pipe
draw_pipe_col:
    cmp ecx, PIPE_WIDTH
    jge draw_pipe_col_done
    
    mov ebx, eax                ; pipe base column
    add ebx, ecx               ; actual column
    
    ; Bounds check column
    cmp ebx, 0
    jl next_pipe_col
    cmp ebx, SCREEN_W
    jge next_pipe_col
    
    ; Draw top pipe (rows 0 to gapTop-1)
    push ecx
    push edx
    
    xor edi, edi                ; row = 0
draw_top_pipe:
    cmp edi, edx                ; row < gapY?
    jge draw_top_done
    cmp edi, GROUND_ROW
    jge draw_top_done
    
    ; Calculate buffer offset: row * SCREEN_W + col
    push eax
    mov eax, edi
    imul eax, SCREEN_W
    add eax, ebx
    
    ; Check if this is a cap row (row == gapY - 1)
    push edx
    dec edx
    cmp edi, edx
    pop edx
    jne top_body
    
    ; Cap row
    mov BYTE PTR screenChars[eax], 0DBh   ; █ full block
    mov BYTE PTR screenColors[eax], 2Ah   ; green bg, bright green fg
    jmp top_drawn
    
top_body:
    mov BYTE PTR screenChars[eax], 0DBh   ; █ full block
    mov BYTE PTR screenColors[eax], 22h   ; green bg, green fg
    
top_drawn:
    pop eax
    inc edi
    jmp draw_top_pipe
    
draw_top_done:
    pop edx
    pop ecx
    
    ; Draw bottom pipe (rows gapY+gapSize to GROUND_ROW-1)
    push ecx
    push edx
    
    mov edi, edx                ; edi = gapY
    add edi, tempInt2           ; edi = gapY + gapSize = bottom pipe start
    
draw_bottom_pipe:
    cmp edi, GROUND_ROW
    jge draw_bottom_done
    
    ; Buffer offset
    push eax
    mov eax, edi
    imul eax, SCREEN_W
    add eax, ebx
    
    ; Check if cap row (first row of bottom pipe)
    push edx
    add edx, tempInt2
    cmp edi, edx
    pop edx
    jne bottom_body
    
    ; Cap row
    mov BYTE PTR screenChars[eax], 0DBh
    mov BYTE PTR screenColors[eax], 2Ah   ; bright green highlight
    jmp bottom_drawn
    
bottom_body:
    mov BYTE PTR screenChars[eax], 0DBh
    mov BYTE PTR screenColors[eax], 22h   ; solid green
    
bottom_drawn:
    pop eax
    inc edi
    jmp draw_bottom_pipe
    
draw_bottom_done:
    pop edx
    pop ecx
    
next_pipe_col:
    inc ecx
    jmp draw_pipe_col
    
draw_pipe_col_done:
    pop ebx                     ; restore pipe index
    
    add esi, SIZEOF Pipe
    inc ebx
    jmp draw_pipe_loop
    
draw_pipes_done:
    popad
    ret
DrawPipesToBuffer ENDP

; ===================================================================
; DrawBirdToBuffer - Draw the bird character into the screen buffer
; ===================================================================
DrawBirdToBuffer PROC
    pushad
    
    ; Convert birdY to integer row
    fld birdY
    fistp tempInt
    mov eax, tempInt            ; row
    
    ; Bounds check
    cmp eax, 0
    jl bird_done
    cmp eax, GROUND_ROW
    jge bird_done
    
    ; Buffer offset: row * SCREEN_W + BIRD_COL
    imul eax, SCREEN_W
    add eax, BIRD_COL
    
    ; Draw bird character
    ; Use '>' when going right/up, 'v' when falling
    fld birdVelocity
    fcomp zeroF
    fstsw ax
    sahf
    ja bird_falling
    
    ; Going up or neutral
    mov eax, tempInt
    imul eax, SCREEN_W
    add eax, BIRD_COL
    mov BYTE PTR screenChars[eax], '>'
    mov BYTE PTR screenColors[eax], 0Eh    ; yellow on black
    jmp bird_done
    
bird_falling:
    mov eax, tempInt
    imul eax, SCREEN_W
    add eax, BIRD_COL
    mov BYTE PTR screenChars[eax], 'v'
    mov BYTE PTR screenColors[eax], 0Eh    ; yellow on black
    
bird_done:
    popad
    ret
DrawBirdToBuffer ENDP

; ===================================================================
; DrawScoreToBuffer - Write score text into the buffer
; ===================================================================
DrawScoreToBuffer PROC
    pushad
    
    ; "Score: " at row 0, col 1
    lea esi, scoreLabel
    mov edi, 1                  ; column offset into row 0
    
score_label_loop:
    lodsb
    test al, al
    jz score_number
    mov BYTE PTR screenChars[edi], al
    mov BYTE PTR screenColors[edi], 3Fh    ; cyan bg, white fg
    inc edi
    jmp score_label_loop
    
score_number:
    ; Convert score to decimal string and write
    mov eax, score
    call WriteNumToBuffer       ; edi = current position, writes digits
    
    ; "Best: " at row 1, col 1
    lea esi, hiScoreLabel
    mov edi, SCREEN_W
    inc edi                     ; col 1 of row 1
    
hi_label_loop:
    lodsb
    test al, al
    jz hi_number
    mov BYTE PTR screenChars[edi], al
    mov BYTE PTR screenColors[edi], 3Eh    ; cyan bg, yellow fg
    inc edi
    jmp hi_label_loop
    
hi_number:
    mov eax, highScore
    push ebx
    mov bl, 3Eh                 ; color for high score
    call WriteNumToBufferColor
    pop ebx
    
    popad
    ret
DrawScoreToBuffer ENDP

; ===================================================================
; WriteNumToBuffer - Write integer in EAX as decimal to buffer at EDI
; Uses color 3Fh (white on cyan)
; Destroys: eax, ecx, edx, edi
; ===================================================================
WriteNumToBuffer PROC
    push ebx
    mov bl, 3Fh
    call WriteNumToBufferColor
    pop ebx
    ret
WriteNumToBuffer ENDP

; ===================================================================
; WriteNumToBufferColor - Write integer in EAX as decimal at EDI
; Color in BL
; ===================================================================
WriteNumToBufferColor PROC
    push ebp
    mov ebp, esp
    sub esp, 16                 ; local buffer for digits
    
    push ecx
    push edx
    push esi
    
    ; Handle 0 specially
    test eax, eax
    jnz convert_digits
    mov BYTE PTR screenChars[edi], '0'
    mov BYTE PTR screenColors[edi], bl
    inc edi
    jmp write_num_done
    
convert_digits:
    ; Convert to decimal digits (push in reverse)
    lea esi, [ebp - 16]
    xor ecx, ecx               ; digit count
    
digit_loop:
    test eax, eax
    jz write_digits
    xor edx, edx
    push ebx
    mov ebx, 10
    div ebx
    pop ebx
    add dl, '0'
    mov BYTE PTR [esi + ecx], dl
    inc ecx
    jmp digit_loop
    
write_digits:
    ; Write digits in reverse order (most significant first)
    dec ecx
write_digit_loop:
    cmp ecx, 0
    jl write_num_done
    mov al, BYTE PTR [esi + ecx]
    mov BYTE PTR screenChars[edi], al
    mov BYTE PTR screenColors[edi], bl
    inc edi
    dec ecx
    jmp write_digit_loop
    
write_num_done:
    pop esi
    pop edx
    pop ecx
    
    mov esp, ebp
    pop ebp
    ret
WriteNumToBufferColor ENDP

; ===================================================================
; WriteStringToBuffer - Write a null-terminated string centered on a row
; Input: esi = string pointer, eax = row number, bl = color
; NOTE: Uses EDI for buffer index instead of EAX because lodsb
;       would corrupt AL (low byte of EAX).
; ===================================================================
WriteStringToBuffer PROC
    pushad
    
    ; Save color in bh temporarily
    mov bh, bl
    
    ; First, find string length
    push esi
    xor ecx, ecx
strlen_loop:
    cmp BYTE PTR [esi], 0
    je strlen_done
    inc ecx
    inc esi
    jmp strlen_loop
strlen_done:
    pop esi
    
    ; Calculate centered column: (SCREEN_W - len) / 2
    mov edx, SCREEN_W
    sub edx, ecx
    shr edx, 1                 ; edx = start column
    
    ; Calculate buffer offset: row * SCREEN_W + col
    imul eax, SCREEN_W
    add eax, edx
    mov edi, eax               ; edi = buffer offset (safe from lodsb)
    
    ; Write string character by character
write_str_loop:
    mov al, BYTE PTR [esi]     ; load char manually (don't use lodsb)
    test al, al
    jz write_str_done
    mov BYTE PTR screenChars[edi], al
    mov BYTE PTR screenColors[edi], bh
    inc edi
    inc esi
    jmp write_str_loop
    
write_str_done:
    popad
    ret
WriteStringToBuffer ENDP

; ===================================================================
; DrawTitleScreen - Draw title and "Press SPACE" into buffer
; ===================================================================
DrawTitleScreen PROC
    pushad
    
    ; Darken center area for panel effect
    ; Draw panel background rows 7-17, cols 15-64
    mov edi, 7                  ; start row
panel_row:
    cmp edi, 18
    jge panel_done
    mov ecx, 15                 ; start col
panel_col:
    cmp ecx, 65
    jge panel_row_next
    mov eax, edi
    imul eax, SCREEN_W
    add eax, ecx
    mov BYTE PTR screenColors[eax], 00h    ; black bg
    mov BYTE PTR screenChars[eax], ' '
    inc ecx
    jmp panel_col
panel_row_next:
    inc edi
    jmp panel_row
panel_done:
    
    ; "FLAPPY BIRD" centered at row 10
    lea esi, titleStr
    mov eax, 10
    mov bl, 0Eh                 ; yellow on black
    call WriteStringToBuffer
    
    ; "Press SPACE to Start" centered at row 14
    lea esi, startStr
    mov eax, 14
    mov bl, 0Fh                 ; white on black
    call WriteStringToBuffer
    
    popad
    ret
DrawTitleScreen ENDP

; ===================================================================
; BuildScoreString - Build "Score: <n>" or "Best: <n>" into tempStrBuf
; Input: esi = label string, eax = number value
; Output: tempStrBuf filled, null-terminated
; ===================================================================
BuildScoreString PROC
    pushad
    
    mov ebx, eax               ; save number
    lea edi, tempStrBuf
    
    ; Copy label
copy_label:
    mov al, BYTE PTR [esi]
    test al, al
    jz label_done
    mov BYTE PTR [edi], al
    inc esi
    inc edi
    jmp copy_label
    
label_done:
    ; Convert number to string and append
    ; Push digits in reverse
    mov eax, ebx
    test eax, eax
    jnz build_digits
    mov BYTE PTR [edi], '0'
    inc edi
    jmp build_done
    
build_digits:
    push ebp
    mov ebp, esp
    sub esp, 16
    lea esi, [ebp - 16]
    xor ecx, ecx
    
build_digit_loop:
    test eax, eax
    jz build_write
    xor edx, edx
    push ebx
    mov ebx, 10
    div ebx
    pop ebx
    add dl, '0'
    mov BYTE PTR [esi + ecx], dl
    inc ecx
    jmp build_digit_loop
    
build_write:
    dec ecx
build_write_loop:
    cmp ecx, 0
    jl build_digits_done
    mov al, BYTE PTR [esi + ecx]
    mov BYTE PTR [edi], al
    inc edi
    dec ecx
    jmp build_write_loop
    
build_digits_done:
    mov esp, ebp
    pop ebp
    
build_done:
    ; Null-terminate
    mov BYTE PTR [edi], 0
    
    popad
    ret
BuildScoreString ENDP

; ===================================================================
; DrawGameOverScreen - Draw game over overlay into buffer
; ===================================================================
DrawGameOverScreen PROC
    pushad
    
    ; Darken center area for panel
    mov edi, 6
panel_row_go:
    cmp edi, 20
    jge panel_done_go
    mov ecx, 15
panel_col_go:
    cmp ecx, 65
    jge panel_row_next_go
    mov eax, edi
    imul eax, SCREEN_W
    add eax, ecx
    mov BYTE PTR screenColors[eax], 00h
    mov BYTE PTR screenChars[eax], ' '
    inc ecx
    jmp panel_col_go
panel_row_next_go:
    inc edi
    jmp panel_row_go
panel_done_go:
    
    ; "GAME OVER" centered at row 9
    lea esi, gameOverStr
    mov eax, 9
    mov bl, 0Ch                 ; light red on black
    call WriteStringToBuffer
    
    ; Build "Score: <n>" into tempStrBuf, then write centered at row 12
    lea esi, scoreLabel
    mov eax, score
    call BuildScoreString
    lea esi, tempStrBuf
    mov eax, 12
    mov bl, 0Fh                 ; white on black
    call WriteStringToBuffer
    
    ; Build "Best: <n>" into tempStrBuf, then write centered at row 14
    lea esi, hiScoreLabel
    mov eax, highScore
    call BuildScoreString
    lea esi, tempStrBuf
    mov eax, 14
    mov bl, 0Eh                 ; yellow on black
    call WriteStringToBuffer
    
    ; "Press SPACE to Restart" centered at row 17
    lea esi, restartStr
    mov eax, 17
    mov bl, 07h                 ; light gray on black
    call WriteStringToBuffer
    
    popad
    ret
DrawGameOverScreen ENDP

; ===================================================================
; FlushScreenBuffer - Render the buffer to the actual console
; Uses Gotoxy + SetTextColor + WriteChar for each cell
; Optimized: only writes when color/char differ from sky
; ===================================================================
FlushScreenBuffer PROC
    pushad
    
    xor ebx, ebx               ; linear index = 0
    xor ecx, ecx               ; current row = 0
    
flush_row:
    cmp ecx, SCREEN_H
    jge flush_done
    
    xor edx, edx               ; current col = 0
    
flush_col:
    cmp edx, SCREEN_W
    jge flush_row_next
    
    ; Set cursor position
    push edx
    push ecx
    mov dh, cl                  ; row
    mov dl, BYTE PTR [esp + 4]  ; col (saved edx)
    call Gotoxy
    pop ecx
    pop edx
    
    ; Set text color
    push eax
    push ecx
    push edx
    movzx eax, BYTE PTR screenColors[ebx]
    call SetTextColor
    pop edx
    pop ecx
    pop eax
    
    ; Write character
    push eax
    push ecx
    push edx
    movzx eax, BYTE PTR screenChars[ebx]
    call WriteChar
    pop edx
    pop ecx
    pop eax
    
    inc ebx
    inc edx
    jmp flush_col
    
flush_row_next:
    inc ecx
    jmp flush_row
    
flush_done:
    popad
    ret
FlushScreenBuffer ENDP

; ===================================================================
; RenderFrame - Compose and display one frame
; ===================================================================
RenderFrame PROC
    pushad
    
    ; Step 1: Clear buffer with sky + ground
    call ClearScreenBuffer
    
    ; Step 2: Draw pipes
    call DrawPipesToBuffer
    
    ; Step 3: Draw bird
    call DrawBirdToBuffer
    
    ; Step 4: Draw score (always)
    cmp playing, 1
    jne skip_score
    call DrawScoreToBuffer
skip_score:
    
    ; Step 5: Draw overlays
    cmp gameOver, 1
    jne check_title
    call DrawScoreToBuffer      ; show score in corner too
    call DrawGameOverScreen
    jmp do_flush
    
check_title:
    cmp playing, 0
    jne do_flush
    call DrawTitleScreen
    
do_flush:
    ; Step 6: Flush buffer to console
    call FlushScreenBuffer
    
    popad
    ret
RenderFrame ENDP

; ===================================================================
; main - Entry point
; ===================================================================
main PROC
    ; Initialize
    call Randomize              ; seed RNG
    call HideCursor             ; hide blinking cursor
    call Clrscr                 ; clear screen
    call InitGame               ; reset game state
    
    ; Get initial time
    call GetMseconds
    mov lastFrameTime, eax
    
    ; ============== GAME LOOP ==============
game_loop:
    ; --- Timing: wait for frame ---
    call GetMseconds
    mov ebx, eax
    sub ebx, lastFrameTime
    cmp ebx, FRAME_DELAY
    jb game_loop                ; not time for new frame yet
    
    ; Update last frame time
    call GetMseconds
    mov lastFrameTime, eax
    
    ; --- Process Input ---
    call ProcessInput
    
    ; --- Update Game State ---
    cmp playing, 1
    jne skip_update
    cmp gameOver, 1
    je skip_update
    
    call UpdatePhysicsAsm
    call UpdatePipes
    
skip_update:
    ; --- Render ---
    call RenderFrame
    
    ; --- Small sleep to prevent CPU spin ---
    INVOKE Sleep, 1
    
    ; Loop forever (exit via console close)
    jmp game_loop
    
main ENDP

END main
