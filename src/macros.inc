; =============================================================================
; macros.inc - Shared constants and macros for Eclipse Vault
; =============================================================================

; ----- DOS services (INT 21h, value goes in AH) -------------------------------
DOS_READ_KEY     EQU 08h            ; Read one key without echo
DOS_OPEN_FILE    EQU 3Dh            ; Open an existing file
DOS_CLOSE_FILE   EQU 3Eh            ; Close a file handle
DOS_READ_FILE    EQU 3Fh            ; Read from a file handle
DOS_WRITE_FILE   EQU 40h            ; Write to a file handle
DOS_EXIT         EQU 4Ch            ; Terminate with a return code

; ----- BIOS video services (INT 10h, value goes in AH) ------------------------
BIOS_SET_MODE    EQU 00h            ; Set video mode (also clears the screen)
BIOS_WRITE_ATTR  EQU 09h            ; Write character and attribute at cursor
BIOS_TELETYPE    EQU 0Eh            ; Write character and advance the cursor
VIDEO_TEXT_80X25 EQU 03h            ; 80x25 color text mode

; ----- Text attributes (background * 16 + foreground) -------------------------
COLOR_TITLE      EQU 0Eh            ; Yellow
COLOR_BORDER     EQU 05h            ; Magenta
COLOR_MENU       EQU 0Bh            ; Light cyan
COLOR_PROMPT     EQU 0Fh            ; Bright white
COLOR_SUCCESS    EQU 0Ah            ; Light green
COLOR_ERROR      EQU 0Ch            ; Light red

; ----- ASCII codes ------------------------------------------------------------
ASCII_LF         EQU 0Ah
ASCII_CR         EQU 0Dh

; -----------------------------------------------------------------------------
; PRINT_COLOR - Print a zero-terminated string in the given color
; -----------------------------------------------------------------------------
PRINT_COLOR MACRO text, color
    push bx
    push si
    mov  si, OFFSET text
    mov  bl, color
    call PrintColored
    pop  si
    pop  bx
ENDM

; -----------------------------------------------------------------------------
; DOS_CALL - Load AH with a DOS service number and call INT 21h
; -----------------------------------------------------------------------------
DOS_CALL MACRO service
    mov  ah, service
    int  21h
ENDM
