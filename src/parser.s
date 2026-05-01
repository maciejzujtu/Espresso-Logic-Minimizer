// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.equ        SYS_WRITE,     0x2000004

// Directive for storing unintialized variables
// for our operand stack and RPN output.
.section __DATA, __bss; // Read & Write
    .align 3
    output:     .space 256
    stack:      .space 256


// Main file's body that is
// responsible for executing instructions
// in the following orders.
.global    _parser
.section __TEXT, __text; // Read & Execute

_parser:
    STP     x19, x20, [sp, #-48]!
    STP     x21, x22, [sp, #16]
    STP     x23, lr,  [sp, #32]

    MOV     x19, x0     // Assign start of buffer to x0
    ADD     x20, x0, x1 // Assign end of buffer to x1

    ADRP    x21,        output@PAGE
    ADD     x21, x21,   output@PAGEOFF
    
    ADRP    x22,        stack@PAGE
    ADD     x22, x22,   stack@PAGEOFF

_RPN:
    CMP     x19, x20
    B.GE                _flush_operators
    LDRB    w23, [x19], #1

    CMP     w23, #'A'

    CMP     w23, #'Z'

    B                   _RPN


_flush_operators:
    ADRP    x24,        stack@PAGE
    ADD     x24, x24    stack@PAGEOFF
    
_flush_loop:
    CMP     x22, x24
    B.EQ                _print
    LDRB    w25, [x22, #-1]!
    CMP     w25, #'('
    B.EQ                _flush_loop
    STRB    w25, [x21], #1
    B                   _flush_loop


_print:
    ADRP    x1,         output@PAGE
    ADD     x1, x1      output@PAGEOFF
    SUB     x2, x21, x1
    MOV     x0, #1
    LDR     x16,        =SYS_WRITE
    SVC                 #0x80

    LDP     x23, lr,  [sp, #32]
    LDP     x21, x22, [sp, #16]
    LDP     x19, x20, [sp], #48
    RET

