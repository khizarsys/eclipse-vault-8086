; =============================================================================
; Eclipse Vault - Password-protected file locker for DOS
; Target : 8086, DOS (DOSBox or EMU8086)
; Syntax : MASM / TASM
; =============================================================================

INCLUDE macros.inc

.MODEL SMALL
.STACK 200h

.DATA
    msgBorder   DB '  ==========================================', ASCII_CR, ASCII_LF, 0
    msgTitle    DB '          E C L I P S E   V A U L T', ASCII_CR, ASCII_LF, 0
    msgTagline  DB '        8086 Password File Locker', ASCII_CR, ASCII_LF, 0
    msgMenu     DB ASCII_CR, ASCII_LF
                DB '    [1] Set Password', ASCII_CR, ASCII_LF
                DB '    [2] Lock File', ASCII_CR, ASCII_LF
                DB '    [3] Unlock File', ASCII_CR, ASCII_LF
                DB '    [4] Exit', ASCII_CR, ASCII_LF, ASCII_CR, ASCII_LF, 0
    msgChoice   DB '  Select an option (1-4): ', 0
    msgInvalid  DB ASCII_CR, ASCII_LF, '  Invalid option. Press 1, 2, 3 or 4.', ASCII_CR, ASCII_LF, 0
    msgPending  DB ASCII_CR, ASCII_LF, '  This feature is not available yet.', ASCII_CR, ASCII_LF, 0
    msgGoodbye  DB ASCII_CR, ASCII_LF, '  Vault closed. Goodbye.', ASCII_CR, ASCII_LF, 0

.CODE

; -----------------------------------------------------------------------------
; Main - Program entry point and menu loop
; -----------------------------------------------------------------------------
Main PROC
    mov  ax, @DATA
    mov  ds, ax
    mov  es, ax

    call ClearScreen

MenuLoop:
    call ShowMenu
    DOS_CALL DOS_READ_KEY

    cmp  al, '4'
    je   ExitProgram
    cmp  al, '1'
    jb   BadChoice
    cmp  al, '3'
    ja   BadChoice

    PRINT_COLOR msgPending, COLOR_PROMPT
    jmp  MenuLoop

BadChoice:
    PRINT_COLOR msgInvalid, COLOR_ERROR
    jmp  MenuLoop

ExitProgram:
    PRINT_COLOR msgGoodbye, COLOR_SUCCESS
    mov  al, 0
    DOS_CALL DOS_EXIT
Main ENDP

; -----------------------------------------------------------------------------
; ClearScreen - Reset to 80x25 color text mode
; -----------------------------------------------------------------------------
ClearScreen PROC
    mov  ah, BIOS_SET_MODE
    mov  al, VIDEO_TEXT_80X25
    int  10h
    ret
ClearScreen ENDP

; -----------------------------------------------------------------------------
; ShowMenu - Draw the title banner and menu options
; -----------------------------------------------------------------------------
ShowMenu PROC
    PRINT_COLOR msgBorder, COLOR_BORDER
    PRINT_COLOR msgTitle, COLOR_TITLE
    PRINT_COLOR msgTagline, COLOR_MENU
    PRINT_COLOR msgBorder, COLOR_BORDER
    PRINT_COLOR msgMenu, COLOR_MENU
    PRINT_COLOR msgChoice, COLOR_PROMPT
    ret
ShowMenu ENDP

; -----------------------------------------------------------------------------
; PrintColored - Print a zero-terminated string with a color attribute
; Input : DS:SI = string, BL = attribute
; Note  : AH=09h sets the color but does not move the cursor, so AH=0Eh then
;         writes the same character to advance it. CR and LF skip AH=09h.
; -----------------------------------------------------------------------------
PrintColored PROC
    push ax
    push bx
    push cx
    push si
    mov  bh, 0                      ; Video page 0

NextChar:
    lodsb
    cmp  al, 0
    je   PrintDone
    cmp  al, ASCII_CR
    je   AdvanceCursor
    cmp  al, ASCII_LF
    je   AdvanceCursor

    mov  ah, BIOS_WRITE_ATTR
    mov  cx, 1
    int  10h

AdvanceCursor:
    mov  ah, BIOS_TELETYPE
    int  10h
    jmp  NextChar

PrintDone:
    pop  si
    pop  cx
    pop  bx
    pop  ax
    ret
PrintColored ENDP

END Main
