// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Truth Table Generator (in-memory)                   //
// =================================================== //

// Directive for storing uninitialized variables
.section __DATA, __bss
    .align 3
    t_var_list:     .space 26             // Sorted unique variables
    t_var_count:    .space 8              // Number of unique vars
    t_eval_stack:   .space 32             // RPN eval stack
    t_assign:       .space 26             // Current variable assignments (0/1)
    .global tt_buf
    tt_buf:         .space 2048           // Shared truth table buffer

.global    _truth
.section __TEXT, __text

// _truth(rpn_buf=x0, rpn_len=x1)
// Generates truth table into tt_buf (global).
// Returns: x0 = tt_buf address, x1 = total bytes written

_truth:
    STP     x19, x20, [sp, #-96]!
    STP     x21, x22, [sp, #16]
    STP     x23, x24, [sp, #32]
    STP     x25, x26, [sp, #48]
    STP     x27, x28, [sp, #64]
    STR     lr,      [sp, #80]

    // Save RPN parameters
    MOV     x19, x0                     // x19 = RPN start
    MOV     x20, x1                     // x20 = RPN length
    ADD     x20, x19, x20               // x20 = RPN end
    MOV     x25, x20                    // Save RPN end in x25

    // Step 1: Scan RPN to find unique variables
    ADRP    x21,        t_var_list@PAGE
    ADD     x21, x21,   t_var_list@PAGEOFF
    MOV     x22, #0                     // x22 = variable count
    MOV     x23, x19                    // x23 = scan pointer

_t_scan:
    CMP     x23, x20
    B.EQ    _t_var_done
    LDRB    w24, [x23], #1              // Load RPN byte

    CMP     w24, #'A'
    B.LT    _t_scan
    CMP     w24, #'Z'
    B.GT    _t_scan

    // Check if variable already in list
    MOV     x27, #0
_t_chk_dup:
    CMP     x27, x22
    B.EQ    _t_add_var
    LDRB    w26, [x21, x27]
    CMP     w24, w26
    B.EQ    _t_scan
    ADD     x27, x27, #1
    B       _t_chk_dup

_t_add_var:
    STRB    w24, [x21, x22]
    ADD     x22, x22, #1
    B       _t_scan

_t_var_done:
    // Store variable count
    ADRP    x26,        t_var_count@PAGE
    ADD     x26, x26,   t_var_count@PAGEOFF
    STR     x22, [x26]
    MOV     x23, x22                    // x23 = N (saved for return)

    // Step 2: Set up tt_buf write pointer
    ADRP    x24,        tt_buf@PAGE
    ADD     x24, x24,   tt_buf@PAGEOFF  // x24 = tt_buf pointer

    // Write header byte (N)
    STRB    w22, [x24], #1              // tt_buf[0] = N

    // Step 3: Compute total rows = 1 << N
    MOV     x28, #1
    LSL     x28, x28, x22               // x28 = 2^N (total rows)
    MOV     x26, #0                     // x26 = row counter

    // Prepare assignment array
    ADRP    x20,        t_assign@PAGE
    ADD     x20, x20,   t_assign@PAGEOFF

_t_row_loop:
    CMP     x26, x28
    B.EQ    _t_done

    // Fill assignment array: bit (N-1-j) of x26 → assign[j]
    MOV     x27, #0
_t_fill_assign:
    CMP     x27, x22
    B.EQ    _t_eval

    SUB     w0, w22, w27
    SUB     w0, w0, #1
    LSR     w1, w26, w0
    AND     w1, w1, #1
    STRB    w1, [x20, x27]

    ADD     x27, x27, #1
    B       _t_fill_assign

_t_eval:
    // Evaluate RPN with current assignments
    BL      _t_eval_rpn
    // w0 = result (0 or 1)

    // Write row to tt_buf: N assignment bytes + 1 result byte
    MOV     x27, #0
_t_copy_row:
    CMP     x27, x22
    B.EQ    _t_copy_done
    LDRB    w1, [x20, x27]
    STRB    w1, [x24], #1               // tt_buf[ptr++] = assign
    ADD     x27, x27, #1
    B       _t_copy_row
_t_copy_done:
    STRB    w0, [x24], #1               // tt_buf[ptr++] = result

    ADD     x26, x26, #1                // Next row
    B       _t_row_loop

_t_done:
    // Return x0 = tt_buf address, x1 = bytes written
    ADRP    x0,         tt_buf@PAGE
    ADD     x0, x0,     tt_buf@PAGEOFF
    SUB     x1, x24, x0                 // bytes written = ptr - start

    LDR     lr,      [sp, #80]
    LDP     x27, x28, [sp, #64]
    LDP     x25, x26, [sp, #48]
    LDP     x23, x24, [sp, #32]
    LDP     x21, x22, [sp, #16]
    LDP     x19, x20, [sp], #96
    RET

// ==========================================
// RPN EVALUATOR
// Uses t_assign (global) for variable values
// Uses t_var_list / t_var_count for mapping
// Returns result in w0
// ==========================================

_t_eval_rpn:
    ADRP    x9,         t_eval_stack@PAGE
    ADD     x9, x9,     t_eval_stack@PAGEOFF
    MOV     x10, x9                     // x10 = stack pointer

    ADRP    x11,        t_var_list@PAGE
    ADD     x11, x11,   t_var_list@PAGEOFF
    ADRP    x12,        t_var_count@PAGE
    ADD     x12, x12,   t_var_count@PAGEOFF
    LDR     x12, [x12]                  // x12 = N
    ADRP    x13,        t_assign@PAGE
    ADD     x13, x13,   t_assign@PAGEOFF

    MOV     x14, x19                    // x14 = RPN pointer
    MOV     x15, x25                    // x15 = RPN end

_t_eval_loop:
    CMP     x14, x15
    B.EQ    _t_eval_done
    LDRB    w0, [x14], #1

    // Check for operand A-Z
    CMP     w0, #'A'
    B.LT    _t_eval_op
    CMP     w0, #'Z'
    B.GT    _t_eval_op

    // Find variable index
    MOV     x16, #0
_t_find_idx:
    LDRB    w1, [x11, x16]
    CMP     w0, w1
    B.EQ    _t_found
    ADD     x16, x16, #1
    B       _t_find_idx
_t_found:
    LDRB    w1, [x13, x16]
    STRB    w1, [x10], #1
    B       _t_eval_loop

_t_eval_op:
    CMP     w0, #'~'
    B.NE    _t_chk_and

    // NOT: pop a, push !a
    LDRB    w1, [x10, #-1]!
    EOR     w1, w1, #1
    STRB    w1, [x10], #1
    B       _t_eval_loop

_t_chk_and:
    CMP     w0, #'&'
    B.NE    _t_chk_xor

    // AND: pop b, pop a, push a & b
    LDRB    w1, [x10, #-1]!             // b
    LDRB    w2, [x10, #-1]!             // a
    AND     w1, w1, w2
    STRB    w1, [x10], #1
    B       _t_eval_loop

_t_chk_xor:
    CMP     w0, #'^'
    B.NE    _t_chk_or

    // XOR: pop b, pop a, push a ^ b
    LDRB    w1, [x10, #-1]!             // b
    LDRB    w2, [x10, #-1]!             // a
    EOR     w1, w1, w2
    STRB    w1, [x10], #1
    B       _t_eval_loop

_t_chk_or:
    CMP     w0, #'|'
    B.NE    _t_eval_loop

    // OR: pop b, pop a, push a | b
    LDRB    w1, [x10, #-1]!             // b
    LDRB    w2, [x10, #-1]!             // a
    ORR     w1, w1, w2
    STRB    w1, [x10], #1
    B       _t_eval_loop

_t_eval_done:
    LDRB    w0, [x10, #-1]
    RET
