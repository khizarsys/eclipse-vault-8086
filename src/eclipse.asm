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

    msgCurrent  DB ASCII_CR, ASCII_LF, '  Enter password: ', 0
    msgNew      DB ASCII_CR, ASCII_LF, '  New password (4-16 characters): ', 0
    msgConfirm  DB '  Confirm password: ', 0
    msgShort    DB '  Password must be at least 4 characters.', ASCII_CR, ASCII_LF, 0
    msgMismatch DB '  Passwords do not match.', ASCII_CR, ASCII_LF, 0
    msgSaved    DB '  Password saved.', ASCII_CR, ASCII_LF, 0
    msgSaveErr  DB '  Error: could not write VAULT.DAT.', ASCII_CR, ASCII_LF, 0
    msgWrong    DB '  Incorrect password.', ASCII_CR, ASCII_LF, 0
    msgLockout  DB '  Too many failed attempts. Vault locked.', ASCII_CR, ASCII_LF, 0
    msgNewLine  DB ASCII_CR, ASCII_LF, 0

    vaultName   DB 'VAULT.DAT', 0
    vaultRecord LABEL BYTE
    vaultMagic  DB 'EV'
    vaultHash   DW 0
    hasPassword DB 0

    passLen     DW 0
    passBuf     DB MAX_PASSWORD DUP (0)
    confirmLen  DW 0
    confirmBuf  DB MAX_PASSWORD DUP (0)

.CODE

; -----------------------------------------------------------------------------
; Main - Program entry point and menu loop
; -----------------------------------------------------------------------------
Main PROC
    mov  ax, @DATA
    mov  ds, ax
    mov  es, ax

    cld                             ; String operations move forward
    call ClearScreen
    call LoadVault

MenuLoop:
    call ShowMenu
    DOS_CALL DOS_READ_KEY

    cmp  al, '1'
    je   ChoiceSetPassword
    cmp  al, '2'
    je   ChoicePending
    cmp  al, '3'
    je   ChoicePending
    cmp  al, '4'
    je   ExitProgram

    PRINT_COLOR msgInvalid, COLOR_ERROR
    jmp  MenuLoop

ChoiceSetPassword:
    call SetPassword
    jmp  MenuLoop

ChoicePending:
    PRINT_COLOR msgPending, COLOR_PROMPT
    jmp  MenuLoop

ExitProgram:
    PRINT_COLOR msgGoodbye, COLOR_SUCCESS
    mov  al, EXIT_OK
    DOS_CALL DOS_EXIT
Main ENDP

; -----------------------------------------------------------------------------
; SetPassword - Create or change the vault password
; Note : An existing password must be verified before it can be replaced.
; -----------------------------------------------------------------------------
SetPassword PROC
    cmp  hasPassword, 1
    jne  AskNewPassword
    mov  ax, vaultHash
    call VerifyPassword

AskNewPassword:
    PRINT_COLOR msgNew, COLOR_PROMPT
    call ReadPassword
    cmp  passLen, MIN_PASSWORD
    jae  KeepNewPassword
    PRINT_COLOR msgShort, COLOR_ERROR
    jmp  SetPasswordDone

KeepNewPassword:
    mov  si, OFFSET passBuf         ; Keep a copy for the confirmation check
    mov  di, OFFSET confirmBuf
    mov  cx, passLen
    mov  confirmLen, cx
    rep  movsb

    PRINT_COLOR msgConfirm, COLOR_PROMPT
    call ReadPassword
    mov  cx, passLen
    cmp  cx, confirmLen
    jne  PasswordMismatch
    mov  si, OFFSET passBuf
    mov  di, OFFSET confirmBuf
    repe cmpsb
    jne  PasswordMismatch

    call HashPassword
    mov  vaultHash, ax
    call SaveVault
    jc   SaveFailed
    mov  hasPassword, 1
    PRINT_COLOR msgSaved, COLOR_SUCCESS
    jmp  SetPasswordDone

SaveFailed:
    PRINT_COLOR msgSaveErr, COLOR_ERROR
    jmp  SetPasswordDone

PasswordMismatch:
    PRINT_COLOR msgMismatch, COLOR_ERROR

SetPasswordDone:
    call WipePasswords
    ret
SetPassword ENDP

; -----------------------------------------------------------------------------
; VerifyPassword - Prompt until the password matches or attempts run out
; Input : AX = expected hash
; Note  : Returns only on success. The program exits after the final failure.
; -----------------------------------------------------------------------------
VerifyPassword PROC
    push bx
    push cx
    mov  bx, ax
    mov  cx, MAX_ATTEMPTS

VerifyAttempt:
    PRINT_COLOR msgCurrent, COLOR_PROMPT
    call ReadPassword
    call HashPassword
    cmp  ax, bx
    je   VerifySuccess
    PRINT_COLOR msgWrong, COLOR_ERROR
    loop VerifyAttempt

    call WipePasswords
    PRINT_COLOR msgLockout, COLOR_ERROR
    mov  al, EXIT_LOCKOUT
    DOS_CALL DOS_EXIT

VerifySuccess:
    pop  cx
    pop  bx
    ret
VerifyPassword ENDP

; -----------------------------------------------------------------------------
; ReadPassword - Read a masked password into passBuf and passLen
; Note : Shows '*' per character and supports Backspace.
; -----------------------------------------------------------------------------
ReadPassword PROC
    push ax
    push bx
    push di
    mov  di, OFFSET passBuf
    mov  passLen, 0

ReadKey:
    DOS_CALL DOS_READ_KEY
    cmp  al, 0                      ; Extended key: discard its second byte
    je   DiscardExtended
    cmp  al, ASCII_CR
    je   ReadDone
    cmp  al, ASCII_BS
    je   HandleBackspace
    cmp  al, ASCII_SPACE            ; Accept printable ASCII only
    jb   ReadKey
    cmp  al, ASCII_TILDE
    ja   ReadKey
    cmp  passLen, MAX_PASSWORD
    jae  ReadKey

    stosb
    inc  passLen
    mov  al, '*'
    call PrintChar
    jmp  ReadKey

DiscardExtended:
    DOS_CALL DOS_READ_KEY
    jmp  ReadKey

HandleBackspace:
    cmp  passLen, 0
    je   ReadKey
    dec  di
    dec  passLen
    mov  al, ASCII_BS               ; Erase the '*' from the screen
    call PrintChar
    mov  al, ASCII_SPACE
    call PrintChar
    mov  al, ASCII_BS
    call PrintChar
    jmp  ReadKey

ReadDone:
    PRINT_COLOR msgNewLine, COLOR_PROMPT
    pop  di
    pop  bx
    pop  ax
    ret
ReadPassword ENDP

; -----------------------------------------------------------------------------
; HashPassword - Compute a 16-bit hash of passBuf
; Output: AX = hash
; -----------------------------------------------------------------------------
HashPassword PROC
    push bx
    push cx
    push dx
    push si
    mov  si, OFFSET passBuf
    mov  cx, passLen
    mov  bx, HASH_SEED
    jcxz HashDone

HashNext:
    mov  ax, HASH_MULTIPLIER
    mul  bx                         ; hash = hash * 33
    mov  bl, [si]
    mov  bh, 0
    add  ax, bx                     ; hash = hash + character
    rol  ax, 1                      ; Spread bits across the word
    mov  bx, ax
    inc  si
    loop HashNext

HashDone:
    mov  ax, bx
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret
HashPassword ENDP

; -----------------------------------------------------------------------------
; WipePasswords - Clear plaintext passwords from memory
; -----------------------------------------------------------------------------
WipePasswords PROC
    push ax
    push cx
    push di
    mov  al, 0
    mov  di, OFFSET passBuf
    mov  cx, MAX_PASSWORD
    rep  stosb
    mov  di, OFFSET confirmBuf
    mov  cx, MAX_PASSWORD
    rep  stosb
    mov  passLen, 0
    mov  confirmLen, 0
    pop  di
    pop  cx
    pop  ax
    ret
WipePasswords ENDP

; -----------------------------------------------------------------------------
; LoadVault - Load the saved password hash from VAULT.DAT, if present
; -----------------------------------------------------------------------------
LoadVault PROC
    mov  dx, OFFSET vaultName
    mov  al, 0                      ; Read-only access
    DOS_CALL DOS_OPEN_FILE
    jc   LoadDone

    mov  bx, ax
    mov  dx, OFFSET vaultRecord
    mov  cx, VAULT_REC_SIZE
    DOS_CALL DOS_READ_FILE
    jc   LoadClose
    cmp  ax, VAULT_REC_SIZE
    jne  LoadClose
    cmp  vaultMagic, 'E'
    jne  LoadClose
    cmp  vaultMagic+1, 'V'
    jne  LoadClose
    mov  hasPassword, 1

LoadClose:
    DOS_CALL DOS_CLOSE_FILE

LoadDone:
    ret
LoadVault ENDP

; -----------------------------------------------------------------------------
; SaveVault - Write the password hash to VAULT.DAT
; Output: CF set on error
; -----------------------------------------------------------------------------
SaveVault PROC
    mov  vaultMagic, 'E'
    mov  vaultMagic+1, 'V'
    mov  dx, OFFSET vaultName
    mov  cx, 0                      ; Normal file attribute
    DOS_CALL DOS_CREATE_FILE
    jc   SaveDone

    mov  bx, ax
    mov  dx, OFFSET vaultRecord
    mov  cx, VAULT_REC_SIZE
    DOS_CALL DOS_WRITE_FILE
    jc   SaveCloseError
    cmp  ax, VAULT_REC_SIZE
    jne  SaveCloseError
    DOS_CALL DOS_CLOSE_FILE
    jmp  SaveDone

SaveCloseError:
    DOS_CALL DOS_CLOSE_FILE
    stc

SaveDone:
    ret
SaveVault ENDP

; -----------------------------------------------------------------------------
; PrintChar - Print the character in AL at the cursor
; -----------------------------------------------------------------------------
PrintChar PROC
    push ax
    push bx
    mov  ah, BIOS_TELETYPE
    mov  bh, 0
    int  10h
    pop  bx
    pop  ax
    ret
PrintChar ENDP

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
