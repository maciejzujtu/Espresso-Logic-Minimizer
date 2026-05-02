// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //


// Assembly file responsible for reading inputs from .bin input file
// that will be later sent to 'parser.s' file to convert input to RPN


// Preprocessor directives to make this slightly
// more readable and easier to understand.
.equ        SYSCALL_CLASS, 0x2000000   
.equ        SYS_EXIT,      0x2000001
.equ        SYS_READ,      0x2000003
.equ        SYS_WRITE,     0x2000004
.equ        SYS_OPEN,      0x2000005
.equ        SYS_CLOSE,     0x2000006

.equ        STDOUT,         1
.equ        O_RDONLY,       0
.equ        BUF_SIZE,       1024


// Directive for storing already initialized variables
// like our path or error messages.
.section __DATA, __data; // Read & Write
    file_path:      .asciz  "/Users/maciej/Desktop/XORcist/input.bin"   // Boolean Logic Expression path
    err_msg:        .ascii "Failed to open/read file\n"                 // Error Message whilst reading
    .equ            err_len, . - err_msg                                // Length of our Error Message


// Directives for storing unitialized variables
// like our buffer to read data .bin files
.section __DATA, __bss; // Read & Write
    buffer:         .space BUF_SIZE



// This is our main file body that is
// responsible for executing instructions
// as per in README.md

.global    _main
.section __TEXT, __text; // Read & Execute

_main:
    // This is our program prologue needed for assembly file to just work
    // we store Frame Pointer and Link Register to Stack.
    STP     fp, lr, [sp, #-16]!
    MOV     fp, sp                      // Now we copy Stack to Frame
    
    //  x0  holds MEM address to our file_path variable
    //  x1  holds numerical value of our flag arguments
    //  x16 loads and stores class SYS_OPEN (its index)

    ADRP    x0,     file_path@PAGE
    ADD     x0, x0, file_path@PAGEOFF
    MOV     x1,     #O_RDONLY
    LDR     x16,    =SYS_OPEN           // === LDR x16, [PC, #offset]

    // Supervision Call interrupts the instruction
    // process and switches to Kernel.
    SVC             #0x80

    // Branch is equivalent of GOTO instruction
    // but here there's also an if statement 
    B.CS            _error

    // After executing SVC the address x0 is
    // our file descriptor to .bin file
    MOV     x19, x0

_read:
    MOV     x0, x19

    ADRP    x1,     buffer@PAGE
    ADD     x1, x1, buffer@PAGEOFF
    MOV     x2,     #BUF_SIZE
    LDR     x16,    =SYS_READ
    SVC             #0x80

    B.CS            _error
    CBZ     x0,     _close

    MOV     x20, x0
    ADRP    x0,     buffer@PAGE
    ADD     x0, x0, buffer@PAGEOFF
    MOV     x1, x20
    
    BL              _parser
    MOV             x20, x0                     // Save RPN length
    ADRP            x0,     output@PAGE
    ADD             x0, x0, output@PAGEOFF
    MOV             x1, x20
    BL              _truth                      // Generate truth table
    BL              _minimize                   // Minimize via Espresso
    B               _close

_close:
    MOV     x0, x19
    LDR     x16,    =SYS_CLOSE
    SVC             #0x80

    MOV     x0, #0
    B       _exit

_error:
    MOV     x0,     #STDOUT
    ADRP    x1,     err_msg@PAGE
    ADD     x1, x1, err_msg@PAGEOFF
    MOV     x2,     #err_len
    LDR     x16,    =SYS_WRITE
    SVC             #0x80

    MOV     x0, #1

_exit:
    LDP     fp, lr, [sp], #16

    LDR     x16,    =SYS_EXIT
    SVC             #0x80