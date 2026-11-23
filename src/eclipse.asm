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

    msgFileAsk  DB ASCII_CR, ASCII_LF, '  File name (8.3 format): ', 0
    msgNoPass   DB ASCII_CR, ASCII_LF, '  Set a password first (option 1).', ASCII_CR, ASCII_LF, 0
    msgBadName  DB '  Error: invalid file name. Use the 8.3 format.', ASCII_CR, ASCII_LF, 0
    msgIsLocked DB '  Error: this file is already locked.', ASCII_CR, ASCII_LF, 0
    msgExists   DB '  Error: output file already exists.', ASCII_CR, ASCII_LF, 0
    msgNotFound DB '  Error: file not found.', ASCII_CR, ASCII_LF, 0
    msgNoPath   DB '  Error: path not found.', ASCII_CR, ASCII_LF, 0
    msgNoHandle DB '  Error: too many open files.', ASCII_CR, ASCII_LF, 0
    msgDenied   DB '  Error: access denied.', ASCII_CR, ASCII_LF, 0
    msgFileErr  DB '  Error: file operation failed.', ASCII_CR, ASCII_LF, 0
    msgLocked   DB '  File locked. Encrypted copy: ', 0

    badChars    DB '\/:*?"<>|+=;,[] '
    BAD_CHARS_LEN EQU $ - badChars
    lockExt     DB '.LCK', 0
    LOCK_EXT_LEN EQU $ - lockExt

    fileName    DB NAME_SIZE DUP (0)
    lockName    DB NAME_SIZE DUP (0)
    inHandle    DW 0
    outHandle   DW 0
    keyState    DW 0
    keyIndex    DW 0

    lockHeader  LABEL BYTE
    hdrMagic    DB 'EVLT'
    hdrName     DB NAME_SIZE DUP (0)
    hdrHash     DW 0

    ioBuffer    DB IO_BUFFER_SIZE DUP (0)

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
    je   ChoiceLock
    cmp  al, '3'
    je   ChoicePending
    cmp  al, '4'
    je   ExitProgram

    PRINT_COLOR msgInvalid, COLOR_ERROR
    jmp  MenuLoop

ChoiceSetPassword:
    call SetPassword
    jmp  MenuLoop

ChoiceLock:
    call LockFile
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
    cmp  passLen, MIN_PASSWORD      ; A short password can never be valid
    jb   VerifyRejected
    call HashPassword
    cmp  ax, bx
    je   VerifySuccess

VerifyRejected:
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
; LockFile - Encrypt a file into NAME.LCK and keep the original
; Note : A partial output file is deleted if any write fails.
; -----------------------------------------------------------------------------
LockFile PROC
    call PrepareLock
    jc   LockExit
    call OpenLockFiles
    jc   LockExit
    call WriteLockedData
    jc   LockWriteFailed
    call CloseStreams
    jc   LockCloseFailed

    PRINT_COLOR msgLocked, COLOR_SUCCESS
    PRINT_COLOR lockName, COLOR_SUCCESS
    PRINT_COLOR msgNewLine, COLOR_SUCCESS
    jmp  LockExit

LockWriteFailed:
    call CloseStreams

LockCloseFailed:
    mov  dx, OFFSET lockName
    DOS_CALL DOS_DELETE_FILE
    PRINT_COLOR msgFileErr, COLOR_ERROR

LockExit:
    call WipePasswords
    ret
LockFile ENDP

; -----------------------------------------------------------------------------
; PrepareLock - Collect and validate the file name, then verify the password
; Output: CF set if the operation should stop
; -----------------------------------------------------------------------------
PrepareLock PROC
    cmp  hasPassword, 1
    je   PrepareAskName
    PRINT_COLOR msgNoPass, COLOR_ERROR
    stc
    ret

PrepareAskName:
    PRINT_COLOR msgFileAsk, COLOR_PROMPT
    call ReadFileName
    jnc  PrepareCheckExt
    PRINT_COLOR msgBadName, COLOR_ERROR
    stc
    ret

PrepareCheckExt:
    call HasLockExtension
    jnc  PrepareVerify
    PRINT_COLOR msgIsLocked, COLOR_ERROR
    stc
    ret

PrepareVerify:
    call BuildLockName
    mov  ax, vaultHash
    call VerifyPassword
    clc
    ret
PrepareLock ENDP

; -----------------------------------------------------------------------------
; OpenLockFiles - Open the source file and create the .LCK output
; Output: CF set on error (message already shown, no handles left open)
; -----------------------------------------------------------------------------
OpenLockFiles PROC
    mov  dx, OFFSET fileName
    mov  al, 0
    DOS_CALL DOS_OPEN_FILE
    jc   OpenSourceFailed
    mov  inHandle, ax

    mov  dx, OFFSET lockName
    call EnsureMissing
    jc   OpenCloseSource

    mov  dx, OFFSET lockName
    mov  cx, 0
    DOS_CALL DOS_CREATE_FILE
    jc   OpenCreateFailed
    mov  outHandle, ax
    clc
    ret

OpenCreateFailed:
    call ShowDosError

OpenCloseSource:
    mov  bx, inHandle
    DOS_CALL DOS_CLOSE_FILE
    stc
    ret

OpenSourceFailed:
    call ShowDosError
    stc
    ret
OpenLockFiles ENDP

; -----------------------------------------------------------------------------
; EnsureMissing - Refuse to overwrite an existing file
; Input : DS:DX = file name
; Output: CF set if the file exists or cannot be checked
; -----------------------------------------------------------------------------
EnsureMissing PROC
    mov  al, 0
    DOS_CALL DOS_OPEN_FILE
    jnc  MissingFileExists
    cmp  ax, DOS_ERR_NOT_FOUND
    je   MissingOk
    call ShowDosError
    stc
    ret

MissingFileExists:
    mov  bx, ax
    DOS_CALL DOS_CLOSE_FILE
    PRINT_COLOR msgExists, COLOR_ERROR
    stc
    ret

MissingOk:
    clc
    ret
EnsureMissing ENDP

; -----------------------------------------------------------------------------
; WriteLockedData - Write the header followed by the encrypted contents
; Output: CF set on error
; -----------------------------------------------------------------------------
WriteLockedData PROC
    mov  si, OFFSET fileName
    mov  di, OFFSET hdrName
    mov  cx, NAME_SIZE
    rep  movsb
    mov  ax, vaultHash
    mov  hdrHash, ax

    mov  bx, outHandle
    mov  dx, OFFSET lockHeader
    mov  cx, HEADER_SIZE
    call WriteExact
    jc   WriteLockedDone

    call InitKeystream
    call CryptStream

WriteLockedDone:
    ret
WriteLockedData ENDP

; -----------------------------------------------------------------------------
; CryptStream - Copy inHandle to outHandle through the XOR keystream
; Output: CF set on error
; -----------------------------------------------------------------------------
CryptStream PROC
CryptNextBlock:
    mov  bx, inHandle
    mov  dx, OFFSET ioBuffer
    mov  cx, IO_BUFFER_SIZE
    DOS_CALL DOS_READ_FILE
    jc   CryptDone
    cmp  ax, 0                      ; Zero bytes read means end of file (CF=0)
    je   CryptDone

    mov  cx, ax
    mov  si, OFFSET ioBuffer
    call CryptBuffer
    mov  bx, outHandle
    mov  dx, OFFSET ioBuffer
    call WriteExact
    jnc  CryptNextBlock

CryptDone:
    ret
CryptStream ENDP

; -----------------------------------------------------------------------------
; CryptBuffer - XOR a buffer with the keystream (same call encrypts/decrypts)
; Input : DS:SI = buffer, CX = byte count
; -----------------------------------------------------------------------------
CryptBuffer PROC
    push ax
    push bx
    push cx
    push dx
    push si
    mov  bx, keyIndex

CryptNextByte:
    mov  ax, keyState               ; state = state * A + C
    mov  dx, KEY_MULTIPLIER
    mul  dx
    add  ax, KEY_INCREMENT
    mov  keyState, ax

    mov  al, ah                     ; High byte has the best distribution
    xor  al, passBuf[bx]            ; Mix in the password
    xor  [si], al

    inc  bx                         ; Cycle through the password
    cmp  bx, passLen
    jb   CryptKeepIndex
    mov  bx, 0

CryptKeepIndex:
    inc  si
    loop CryptNextByte

    mov  keyIndex, bx
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret
CryptBuffer ENDP

; -----------------------------------------------------------------------------
; InitKeystream - Derive the starting key state from the password
; Note : Uses a different function from HashPassword, so the stored hash is
;        not the key.
; -----------------------------------------------------------------------------
InitKeystream PROC
    push ax
    push bx
    push cx
    push si
    mov  si, OFFSET passBuf
    mov  cx, passLen
    mov  bx, KEY_SEED

KeyNextChar:
    mov  al, [si]
    mov  ah, al                     ; Copy the character into both halves
    rol  bx, 1
    rol  bx, 1
    rol  bx, 1
    xor  bx, ax
    inc  si
    loop KeyNextChar

    mov  keyState, bx
    mov  keyIndex, 0
    pop  si
    pop  cx
    pop  bx
    pop  ax
    ret
InitKeystream ENDP

; -----------------------------------------------------------------------------
; WriteExact - Write CX bytes and treat a short write as an error
; Input : BX = handle, DS:DX = data, CX = byte count
; Output: CF set on error
; -----------------------------------------------------------------------------
WriteExact PROC
    DOS_CALL DOS_WRITE_FILE
    jc   WriteExactDone
    cmp  ax, cx
    je   WriteExactDone             ; Equal values leave CF clear
    stc

WriteExactDone:
    ret
WriteExact ENDP

; -----------------------------------------------------------------------------
; CloseStreams - Close both file handles
; Output: CF set if closing the output failed
; -----------------------------------------------------------------------------
CloseStreams PROC
    mov  bx, inHandle
    DOS_CALL DOS_CLOSE_FILE
    mov  bx, outHandle
    DOS_CALL DOS_CLOSE_FILE
    ret
CloseStreams ENDP

; -----------------------------------------------------------------------------
; ReadFileName - Read and validate an uppercase 8.3 name into fileName
; Output: CF set if the name is invalid
; -----------------------------------------------------------------------------
ReadFileName PROC
    mov  di, OFFSET fileName
    mov  cx, 0

NameNextKey:
    DOS_CALL DOS_READ_KEY
    cmp  al, 0
    je   NameExtended
    cmp  al, ASCII_CR
    je   NameDone
    cmp  al, ASCII_BS
    je   NameBackspace
    cmp  al, ASCII_SPACE
    jb   NameNextKey
    cmp  al, ASCII_TILDE
    ja   NameNextKey
    cmp  cx, MAX_NAME_CHARS
    jae  NameNextKey

    cmp  al, 'a'                    ; Convert lowercase to uppercase
    jb   NameStore
    cmp  al, 'z'
    ja   NameStore
    sub  al, 20h

NameStore:
    stosb
    inc  cx
    call PrintChar
    jmp  NameNextKey

NameExtended:
    DOS_CALL DOS_READ_KEY
    jmp  NameNextKey

NameBackspace:
    cmp  cx, 0
    je   NameNextKey
    dec  di
    dec  cx
    mov  al, ASCII_BS
    call PrintChar
    mov  al, ASCII_SPACE
    call PrintChar
    mov  al, ASCII_BS
    call PrintChar
    jmp  NameNextKey

NameDone:
    mov  al, 0
    stosb
    PRINT_COLOR msgNewLine, COLOR_PROMPT
    call ValidateFileName
    ret
ReadFileName ENDP

; -----------------------------------------------------------------------------
; ValidateFileName - Check fileName against the 8.3 rules
; Output: CF set if invalid
; Note  : Paths are rejected, so files stay in the current directory.
; -----------------------------------------------------------------------------
ValidateFileName PROC
    mov  si, OFFSET fileName
    mov  bx, 0                      ; Length of the current name part
    mov  dl, 8                      ; Maximum length of the current part
    mov  dh, 0                      ; Set to 1 after the dot

ValidateNext:
    lodsb
    cmp  al, 0
    je   ValidateEnd
    cmp  al, '.'
    je   ValidateDot

    mov  di, OFFSET badChars
    mov  cx, BAD_CHARS_LEN
    repne scasb
    je   ValidateFail

    inc  bx
    cmp  bl, dl
    ja   ValidateFail
    jmp  ValidateNext

ValidateDot:
    cmp  dh, 1                      ; Only one dot is allowed
    je   ValidateFail
    cmp  bx, 0                      ; The base name cannot be empty
    je   ValidateFail
    mov  dh, 1
    mov  dl, 3
    mov  bx, 0
    jmp  ValidateNext

ValidateEnd:
    cmp  bx, 0                      ; Rejects an empty name and 'NAME.'
    je   ValidateFail
    clc
    ret

ValidateFail:
    stc
    ret
ValidateFileName ENDP

; -----------------------------------------------------------------------------
; HasLockExtension - Check whether fileName ends in .LCK
; Output: CF set if it does
; -----------------------------------------------------------------------------
HasLockExtension PROC
    mov  si, OFFSET fileName

ExtFindDot:
    lodsb
    cmp  al, 0
    je   ExtNoMatch
    cmp  al, '.'
    jne  ExtFindDot

    dec  si                         ; Compare from the dot, including the zero
    mov  di, OFFSET lockExt
    mov  cx, LOCK_EXT_LEN
    repe cmpsb
    jne  ExtNoMatch
    stc
    ret

ExtNoMatch:
    clc
    ret
HasLockExtension ENDP

; -----------------------------------------------------------------------------
; BuildLockName - Build lockName from fileName with a .LCK extension
; -----------------------------------------------------------------------------
BuildLockName PROC
    mov  si, OFFSET fileName
    mov  di, OFFSET lockName

BuildCopyBase:
    lodsb
    cmp  al, 0
    je   BuildAddExt
    cmp  al, '.'
    je   BuildAddExt
    stosb
    jmp  BuildCopyBase

BuildAddExt:
    mov  si, OFFSET lockExt
    mov  cx, LOCK_EXT_LEN
    rep  movsb
    ret
BuildLockName ENDP

; -----------------------------------------------------------------------------
; ShowDosError - Print a message for a DOS error code
; Input : AX = DOS error code
; -----------------------------------------------------------------------------
ShowDosError PROC
    cmp  ax, DOS_ERR_NOT_FOUND
    je   ShowNotFound
    cmp  ax, DOS_ERR_NO_PATH
    je   ShowNoPath
    cmp  ax, DOS_ERR_NO_HANDLE
    je   ShowNoHandle
    cmp  ax, DOS_ERR_DENIED
    je   ShowDenied
    PRINT_COLOR msgFileErr, COLOR_ERROR
    ret

ShowNotFound:
    PRINT_COLOR msgNotFound, COLOR_ERROR
    ret

ShowNoPath:
    PRINT_COLOR msgNoPath, COLOR_ERROR
    ret

ShowNoHandle:
    PRINT_COLOR msgNoHandle, COLOR_ERROR
    ret

ShowDenied:
    PRINT_COLOR msgDenied, COLOR_ERROR
    ret
ShowDosError ENDP

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
