// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Linker:           LD64 ld                           //
// =================================================== //

.equ        SYS_WRITE,     0x2000004
.equ        SYS_EXIT,      0x2000001

// Syntax state machine constants
.equ        STATE_START,       0
.equ        STATE_OPERAND,     1
.equ        STATE_BINOP,       2
.equ        STATE_NOT,         3
.equ        STATE_OPEN_PAREN,  4
.equ        STATE_CLOSE_PAREN, 5

// Directive for storing uninitialized variables
// for our operand stack and RPN output.
.section __DATA, __bss;  // Read & Write
    .global output
    .align 3
    output:     .space 256
    stack:      .space 256

// Main file's body that is responsible for executing 
// instructions in the following orders.
.global    _parser
.section __TEXT, __text; // Read & Execute

_parser:
    STP     x19, x20, [sp, #-64]!
    STP     x21, x22, [sp, #16]
    STP     x23, x26, [sp, #32]
    STP     x27, lr,  [sp, #48]

    MOV     x19, x0     // Assign start of buffer to x19
    ADD     x20, x0, x1 // Assign end of buffer to x20

    ADRP    x21,        output@PAGE
    ADD     x21, x21,   output@PAGEOFF
    
    ADRP    x22,        stack@PAGE
    ADD     x22, x22,   stack@PAGEOFF

    MOV     x26, #STATE_START      // Initial syntax state
    MOV     x27, #0                // Parenthesis counter

// The following program is an implemention of Shunting Yard algoritm
// that evaluates Boole's Algebra infix expressions from buffer and
// returns same expression in postfix (RP) notation.

// =================================================== //
// Input constraints                                   //
//  * Variables are strictly uppercase A-Z letters     //
//  * Variable count limit for singular input is 26    //
//  * The input must be in an infix expression.        //
//  * The operations syntax is ~, &, ^, |              //
// =================================================== //

_RPN:
    CMP     x19, x20
    B.GE    _validate_end
    LDRB    w23, [x19], #1

    // Ignore spaces (no state change)
    CMP     w23, #' '
    B.EQ    _RPN
    CMP     w23, #'\n'
    B.EQ    _error_newline
    CMP     w23, #'\r'
    B.EQ    _error_newline

    // Check if character is an Operand (A-Z)
    CMP     w23, #'A'
    B.LT    _not_upper
    CMP     w23, #'Z'
    B.LE    _handle_operand
_not_upper:
    // Lowercase variables are error
    CMP     w23, #'a'
    B.LT    _not_operand
    CMP     w23, #'z'
    B.GT    _not_operand
    B       _error_lowercase

_not_operand:
    CMP     w23, #'('
    B.EQ    _handle_open_paren
    CMP     w23, #')'
    B.EQ    _handle_close_paren
    CMP     w23, #'~'
    B.EQ    _handle_not
    CMP     w23, #'&'
    B.EQ    _handle_binop
    CMP     w23, #'^'
    B.EQ    _handle_binop
    CMP     w23, #'|'
    B.EQ    _handle_binop
    B       _error_unknown

// ==========================================
// SYNTAX STATE HANDLERS
// ==========================================

_handle_operand:
    // Valid after: START, BINOP, NOT, OPEN_PAREN
    CMP     w26, #STATE_START
    B.EQ    1f
    CMP     w26, #STATE_BINOP
    B.EQ    1f
    CMP     w26, #STATE_NOT
    B.EQ    1f
    CMP     w26, #STATE_OPEN_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    MOV     w26, #STATE_OPERAND
    STRB    w23, [x21], #1
    B       _RPN

_handle_open_paren:
    // Valid after: START, BINOP, NOT, OPEN_PAREN
    CMP     w26, #STATE_START
    B.EQ    1f
    CMP     w26, #STATE_BINOP
    B.EQ    1f
    CMP     w26, #STATE_NOT
    B.EQ    1f
    CMP     w26, #STATE_OPEN_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    MOV     w26, #STATE_OPEN_PAREN
    ADD     w27, w27, #1
    B       _push_stack

_handle_close_paren:
    // Valid after: OPERAND, CLOSE_PAREN
    CMP     w26, #STATE_OPERAND
    B.EQ    1f
    CMP     w26, #STATE_CLOSE_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    CMP     w27, #0
    B.EQ    _error_syntax
    SUB     w27, w27, #1
    MOV     w26, #STATE_CLOSE_PAREN
    B       _handle_rparen

_handle_not:
    // Valid after: START, BINOP, NOT, OPEN_PAREN
    CMP     w26, #STATE_START
    B.EQ    1f
    CMP     w26, #STATE_BINOP
    B.EQ    1f
    CMP     w26, #STATE_NOT
    B.EQ    1f
    CMP     w26, #STATE_OPEN_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    MOV     w26, #STATE_NOT
    B       _handle_operator

_handle_binop:
    // Valid after: OPERAND, CLOSE_PAREN
    CMP     w26, #STATE_OPERAND
    B.EQ    1f
    CMP     w26, #STATE_CLOSE_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    MOV     w26, #STATE_BINOP
    B       _handle_operator

// ==========================================
// END OF INPUT VALIDATION
// ==========================================

_validate_end:
    CMP     w26, #STATE_OPERAND
    B.EQ    1f
    CMP     w26, #STATE_CLOSE_PAREN
    B.EQ    1f
    B       _error_syntax
1:
    CMP     w27, #0
    B.NE    _error_syntax
    B       _flush_operators

// ==========================================
// SHUNTING YARD — OPERATOR PROCESSING
// ==========================================

_handle_operator:
    BL      _get_prec_w23
    MOV     w9, w24                 // Current operator precedence in w9

_op_loop:
    // Check if stack is empty
    ADRP    x24,        stack@PAGE
    ADD     x24, x24,   stack@PAGEOFF
    CMP     x22, x24
    B.EQ    _push_stack

    // Peek top of stack -> w25
    LDRB    w25, [x22, #-1]
    
    // Stop popping if top of stack is '('
    CMP     w25, #'('
    B.EQ    _push_stack

    // Get precedence of stack top (w25) -> w24
    BL      _get_prec_w25

    // If prec(stack_top) < prec(current), push current
    CMP     w24, w9
    B.LT    _push_stack

    // Else, pop stack_top to output, and repeat the check
    LDRB    w25, [x22, #-1]!        // Pop
    STRB    w25, [x21], #1          // Write to output
    B       _op_loop

_push_stack:
    STRB    w23, [x22], #1          // Push w23 to stack
    B       _RPN

_handle_rparen:
    // Pop operators to output until we find '('
    ADRP    x24,        stack@PAGE
    ADD     x24, x24,   stack@PAGEOFF
_rparen_loop:
    CMP     x22, x24
    B.EQ    _RPN
    LDRB    w25, [x22, #-1]!        // Pop
    CMP     w25, #'('
    B.EQ    _RPN                    // Found '(', discard it and move on
    STRB    w25, [x21], #1          // Write popped operator to output
    B       _rparen_loop


// ==========================================
// PRECEDENCE SUBROUTINES
// Returns hierarchy weight in w24
// ~ = 4, & = 3, ^ = 2, | = 1, Other = 0
// ==========================================

_get_prec_w23:
    MOV     w24, #0
    CMP     w23, #'|'
    B.EQ    _prec_1
    CMP     w23, #'^'
    B.EQ    _prec_2
    CMP     w23, #'&'
    B.EQ    _prec_3
    CMP     w23, #'~'
    B.EQ    _prec_4
    RET

_get_prec_w25:
    MOV     w24, #0
    CMP     w25, #'|'
    B.EQ    _prec_1
    CMP     w25, #'^'
    B.EQ    _prec_2
    CMP     w25, #'&'
    B.EQ    _prec_3
    CMP     w25, #'~'
    B.EQ    _prec_4
    RET

_prec_1: 
    MOV w24, #1
    RET
_prec_2: 
    MOV w24, #2
    RET
_prec_3: 
    MOV w24, #3
    RET
_prec_4: 
    MOV w24, #4
    RET

// ==========================================
// FLUSH REMAINING OPERATORS
// ==========================================

_flush_operators:
    ADRP    x24,        stack@PAGE
    ADD     x24, x24,   stack@PAGEOFF
    
_flush_loop:
    CMP     x22, x24
    B.EQ    _print_newline      
    LDRB    w25, [x22, #-1]!
    CMP     w25, #'('
    B.EQ    _flush_loop
    STRB    w25, [x21], #1
    B       _flush_loop

_print_newline:
    // Append a newline character for clean console output
    MOV     w25, #'\n'
    STRB    w25, [x21], #1
    B       _print

_print:
    ADRP    x1,         output@PAGE
    ADD     x1, x1,     output@PAGEOFF
    SUB     x2, x21, x1                 // Calculate output length
    MOV     x9, x2                      // Save length for return value
    MOV     x0, #1                      // STDOUT
    LDR     x16,        =SYS_WRITE
    SVC                 #0x80

    // Epilogue - Restore states
    LDP     x27, lr,  [sp, #48]
    LDP     x23, x26, [sp, #32]
    LDP     x21, x22, [sp, #16]
    LDP     x19, x20, [sp], #64
    MOV     x0, x9                      // Return RPN length in x0
    RET

// ==========================================
// ERROR MESSAGES
// ==========================================
.section __TEXT, __const
msg_lcase:
    .asciz "Error: lowercase variable\n"
msg_newline:
    .asciz "Error: newline character\n"
msg_unknown:
    .asciz "Error: unknown character\n"
msg_syntax:
    .asciz "Error: invalid syntax\n"

// ==========================================
// ERROR HANDLERS
// ==========================================
.section __TEXT, __text
    .balign 4

_error_lowercase:
    ADRP    x1, msg_lcase@PAGE
    ADD     x1, x1, msg_lcase@PAGEOFF
    MOV     x2, #26
    B       _print_error

_error_newline:
    ADRP    x1, msg_newline@PAGE
    ADD     x1, x1, msg_newline@PAGEOFF
    MOV     x2, #25
    B       _print_error

_error_unknown:
    ADRP    x1, msg_unknown@PAGE
    ADD     x1, x1, msg_unknown@PAGEOFF
    MOV     x2, #25
    B       _print_error

_error_syntax:
    ADRP    x1, msg_syntax@PAGE
    ADD     x1, x1, msg_syntax@PAGEOFF
    MOV     x2, #22
    B       _print_error

_print_error:
    MOV     x0, #1
    LDR     x16,        =SYS_WRITE
    SVC                 #0x80
    MOV     x0, #1
    LDR     x16,        =SYS_EXIT
    SVC                 #0x80
