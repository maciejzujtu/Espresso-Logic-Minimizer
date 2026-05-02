// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.include "include/defs.inc"

// Parser assembly file is responsible for reading the
// binary file thrown as argument and validating it to
// ensure the data given fits the syntax.

.globl _parse

.section __TEXT, __text


// --- _parse(fd in x0) ---
_parse:
    // --- prologue ---
    SUB     sp,  sp,    #32             // Reserve 32 bytes for our stack (4 slots)
    STP     fp,  lr,    [sp, #16]       // #4 and #3 slots are reserved for LR and FP
    ADD     fp,  sp,    #16             // Stack pointer is now pointing to FP

    STR     x0,         [fp, #-8]       // Save fd to slot #1

_loop:
    // --- read ---
    LDR     x0,         [fp, #-8]       // Set #1 arg to saved file descriptor
    ADRP    x1,         buffer@PAGE     // Store memory address of our buffer to #2 arg
    ADD     x1,  x1,    buffer@PAGEOFF
    MOV     x2,         #BUF_SIZE       // Set #3 arg to buffer's size
    LDR     x16,        =SYS_READ       // Execute the SYS_READ class with 3 args
    SVC     #0x80                       // Make kernel read the instructions

    B.CS                _return_main    // Check for error
    CBZ     x0,         _return_main    // Check for EOF

    // --- write ---
    MOV     x2,         x0              // Reassign byte count to #3 arg
    MOV     x0,         #STDOUT         // Set STDOUT file descriptor to #1 arg
    ADRP    x1,         buffer@PAGE     // Set buffer's memory address to #2 arg
    ADD     x1,  x1,    buffer@PAGEOFF
    LDR     x16,        =SYS_WRITE      // Execute SYS_WRITE class with 3 args
    SVC     #0x80                       // Make kernel read the instructions

    B                   _loop           // Repeat loop

_return_main:
    // --- epilogue ---
    LDP     fp,  lr,    [sp, #16]       // Load FP and LR from our stack's pointing at 16th byte
    ADD     sp,  sp,    #32             // Shift bytes so that the stack looks like before prologue
    RET                                 // Return to main.s
