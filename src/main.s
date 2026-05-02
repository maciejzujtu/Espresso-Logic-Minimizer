// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// Main assembly file responsible for reading data
// and validating arguments as declared below.

.section  __DATA,   __data
     usage_message:         .ascii "Usage: ./main < FILE\n"
.equ usage_len,             . - usage_message

     error_message:         .ascii "Failed to open file.\n"
.equ error_len,             . - error_message


.section  __DATA,   __bss
.globl buffer
    buffer:                 .space BUF_SIZE


// --- main ---
.global             _main
.section __TEXT,    __text


_main:
    // --- prologue ---
    SUB     sp,  sp,    #32             // Reserve 32 bytes for our stack (4 slots)
    STP     fp,  lr,    [sp, #16]       // #4 and #3 slots are reserved for LR and FP
    ADD     fp,  sp,    #16             // Stack pointer is now pointing to FP

    CMP     w0,         #1              // Assign argc >= 1 to accumulator
    B.GT    _error                      // Throw error if argc > 1

    // --- parser ---
    MOV     x0,         #STDIN          // Set fd to STDIN
    BL      _parse                      // Run _parse program from parser.s

    MOV     w0,         #0              // Set status code to 0
    B       _exit                       // Go to epilogue

_error:
    // --- read ---
    // Similar mechanism except we just use pre-initinalized
    // variables from __DATA section to print out usage prompt

    MOV     x2,         #usage_len      // Set #3 arg to usage length
    MOV     x0,         #STDOUT         // Set STDIN file descriptor to #1 arg
    ADRP    x1,         usage_message@PAGE
    ADD     x1,  x1,    usage_message@PAGEOFF
    LDR     x16,        =SYS_WRITE
    SVC     #0x80

    MOV     w0,         #1              // Set status code to 1

_exit:
    // --- epilogue ---
    LDP     fp,  lr,    [sp, #16]       // Load FP and LR from our stack's pointing at 16th byte
    ADD     sp,  sp,    #32             // Shift bytes so that the stack looks like before prologue

    LDR     x16,        =SYS_EXIT       // Execute SYS_EXIT class
    SVC     #0x80
