; =============================================================================
; macros.inc - Shared constants and macros for Eclipse Vault
; =============================================================================

; ----- DOS services (INT 21h, value goes in AH) -------------------------------
DOS_READ_KEY     EQU 08h            ; Read one key without echo
DOS_CREATE_FILE  EQU 3Ch            ; Create or truncate a file
DOS_OPEN_FILE    EQU 3Dh            ; Open an existing file
DOS_CLOSE_FILE   EQU 3Eh            ; Close a file handle
DOS_READ_FILE    EQU 3Fh            ; Read from a file handle
DOS_WRITE_FILE   EQU 40h            ; Write to a file handle
DOS_DELETE_FILE  EQU 41h            ; Delete a file
DOS_EXIT         EQU 4Ch            ; Terminate with a return code

; ----- DOS error codes (returned in AX when CF is set) ------------------------
DOS_ERR_NOT_FOUND EQU 2
DOS_ERR_NO_PATH   EQU 3
DOS_ERR_NO_HANDLE EQU 4
DOS_ERR_DENIED    EQU 5

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
ASCII_BS         EQU 08h
ASCII_LF         EQU 0Ah
ASCII_CR         EQU 0Dh
ASCII_SPACE      EQU 20h
ASCII_TILDE      EQU 7Eh

; ----- Password rules ---------------------------------------------------------
MIN_PASSWORD     EQU 4              ; Shortest accepted password
MAX_PASSWORD     EQU 16             ; Longest accepted password
MAX_ATTEMPTS     EQU 3              ; Wrong tries before lockout
HASH_SEED        EQU 1505h          ; Starting value for the password hash
HASH_MULTIPLIER  EQU 33             ; Multiplier for the password hash
VAULT_REC_SIZE   EQU 4              ; Magic (2 bytes) + hash (2 bytes)

; ----- Locked file format and encryption --------------------------------------
IO_BUFFER_SIZE   EQU 512            ; Bytes processed per read
NAME_SIZE        EQU 13             ; 8.3 file name plus terminator
MAX_NAME_CHARS   EQU 12             ; 8.3 file name without terminator
HEADER_SIZE      EQU 19             ; Magic (4) + name (13) + hash (2)
KEY_SEED         EQU 0C3A5h         ; Starting value for the key derivation
KEY_MULTIPLIER   EQU 25173          ; Keystream generator multiplier
KEY_INCREMENT    EQU 13849          ; Keystream generator increment

; ----- Program exit codes -----------------------------------------------------
EXIT_OK          EQU 0
EXIT_LOCKOUT     EQU 1

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
