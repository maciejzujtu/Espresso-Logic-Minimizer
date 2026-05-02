// =================================================== //
// Architecture:     ARM64       (Apple, Darwin)       //
// Assembler:        LLVM as                           //
// Espresso Logic Minimizer                            //
// =================================================== //

.equ        SYS_WRITE,     0x2000004
.equ        STDOUT,        1
.equ        MAX_TERMS,     64

// Directive for storing uninitialized variables
.section __DATA, __bss
    .align 3
    m_N:            .space 8                        // Number of variables
    m_on_set:       .space MAX_TERMS * 4            // ON minterms (32-bit each)
    m_off_set:      .space MAX_TERMS * 4            // OFF minterms
    m_on_count:     .space 8                        // |ON|
    m_off_count:    .space 8                        // |OFF|
    m_cover_val:    .space MAX_TERMS * 4            // Implicant values
    m_cover_mask:   .space MAX_TERMS * 4            // Implicant masks
    m_cover_cnt:    .space 8                        // Number of implicants
    m_work_val:     .space MAX_TERMS * 4            // Working values
    m_work_mask:    .space MAX_TERMS * 4            // Working masks
    m_work_cnt:     .space 8                        // Working count
    m_selected:     .space MAX_TERMS                // Selected flags
    m_covered:      .space MAX_TERMS                // Per-minterm covered flags
    m_out_buf:      .space 1024                     // Output buffer
    m_var_names:    .space 26                       // Variable letters

// ===================================================
// MINIMIZE SUBROUTINE  _minimize(tt_buf=x0)
// ===================================================
.global    _minimize
.section __TEXT, __text

_minimize:
    STP     fp, lr, [sp, #-16]!
    MOV     fp, sp

    // x0 = truth table buffer address
    MOV     x20, x0                         // Save buffer address

    // First byte = number of variables N
    LDRB    w0, [x20]
    ADRP    x19,        m_N@PAGE
    ADD     x19, x19,   m_N@PAGEOFF
    STR     x0, [x19]
    MOV     x21,  x0                        // x21 = N

    // Each row is N+1 bytes: N assignment bytes + 1 result byte
    // Number of rows = 1 << N
    MOV     x22,  #1
    LSL     x22, x22, x21                   // x22 = 2^N

    // Initialize ON/OFF pointers
    ADRP    x23,        m_on_set@PAGE
    ADD     x23, x23,   m_on_set@PAGEOFF
    ADRP    x24,        m_off_set@PAGE
    ADD     x24, x24,   m_off_set@PAGEOFF
    MOV     x25,  #0                        // on_count
    MOV     x26,  #0                        // off_count

    // Parse rows from buffer (starting at offset 1)
    ADD     x27, x20, #1                    // x27 = row data pointer
    MOV     x28,  #0                        // row index

_m_parse_rows:
    CMP     x28, x22
    B.EQ    _m_done_parse

    // Read result byte (last byte of row = offset N)
    LDRB    w0, [x27, x21]                  // result = row[N]

    // Pack assignment bytes into a 32-bit minterm value
    MOV     w1, #0                          // minterm value
    MOV     x2, #0                          // byte index

_m_pack:
    CMP     x2, x21
    B.EQ    _m_packed
    LDRB    w3, [x27, x2]
    AND     w3, w3, #1                      // Ensure 0 or 1
    LSL     w3, w3, w2                      // Bit at position x2
    ORR     w1, w1, w3
    ADD     x2, x2, #1
    B       _m_pack

_m_packed:
    CMP     w0, #1
    B.EQ    _m_add_on

    // Add to OFF set
    STR     w1, [x24, x26, LSL #2]
    ADD     x26, x26, #1
    B       _m_next_row

_m_add_on:
    STR     w1, [x23, x25, LSL #2]
    ADD     x25, x25, #1

_m_next_row:
    ADD     x27, x27, x21                   // + N
    ADD     x27, x27, #1                    // + 1 (result byte)
    ADD     x28, x28, #1
    B       _m_parse_rows

_m_done_parse:
    // Store counts
    ADRP    x0, m_on_count@PAGE
    ADD     x0, x0, m_on_count@PAGEOFF
    STR     x25, [x0]
    ADRP    x0, m_off_count@PAGE
    ADD     x0, x0, m_off_count@PAGEOFF
    STR     x26, [x0]

    // If no ON terms, expression is always false (output "0")
    CMP     x25, #0
    B.EQ    _m_output_zero

    // If no OFF terms, expression is always true (output "1")
    CMP     x26, #0
    B.EQ    _m_output_one

    // ==========================================
    // ESPRESSO ALGORITHM
    // ==========================================

    // Initialize cover = ON-set minterms as full implicants
    // Save N and counts into callee-saved regs
    MOV     x19, x21                        // x19 = N
    MOV     x20, x25                        // x20 = on_count
    MOV     x21, x26                        // x21 = off_count

    // Load base addresses
    ADRP    x22,        m_on_set@PAGE
    ADD     x22, x22,   m_on_set@PAGEOFF
    ADRP    x23,        m_off_set@PAGE
    ADD     x23, x23,   m_off_set@PAGEOFF
    ADRP    x24,        m_cover_val@PAGE
    ADD     x24, x24,   m_cover_val@PAGEOFF
    ADRP    x25,        m_cover_mask@PAGE
    ADD     x25, x25,   m_cover_mask@PAGEOFF

    // Full mask = (1 << N) - 1
    MOV     x9,  #1
    LSL     x9,  x9, x19
    SUB     x9,  x9, #1                     // x9 = full_mask

    // Init cover: copy ON-set values, set mask = full_mask
    MOV     x10,  #0
_m_init_cover:
    CMP     x10, x20
    B.EQ    _m_init_done

    LDR     w11, [x22, x10, LSL #2]         // ON value
    STR     w11, [x24, x10, LSL #2]         // cover_val[i]
    STR     w9,  [x25, x10, LSL #2]         // cover_mask[i] = full mask

    ADD     x10, x10, #1
    B       _m_init_cover

_m_init_done:
    MOV     x26, x20                        // cover_cnt = on_count
    MOV     x27, #0                         // best_cost (will set later)
    MOV     x28, #0                         // iteration counter

    // --- ESPRESSO main loop ---
_m_espresso_loop:
    CMP     x28, #3                         // Max 3 iterations
    B.EQ    _m_espresso_done

    // ==========================================
    // EXPAND phase
    // ==========================================
_m_expand:
    MOV     x10, #0                         // i = 0
_m_expand_loop:
    CMP     x10, x26                        // i < cover_cnt?
    B.EQ    _m_expand_done

    LDR     w11, [x24, x10, LSL #2]         // value = cover_val[i]
    LDR     w12, [x25, x10, LSL #2]         // mask  = cover_mask[i]

    // Try expanding each care bit to don't-care
    MOV     x13, #0                         // bit index
_m_expand_bit:
    CMP     x13, x19                        // bit < N?
    B.EQ    _m_expand_next

    // Check if this bit is a care bit (bit in mask)
    MOV     w14, #1
    LSL     w14, w14, w13                   // bit mask for position
    TST     w12, w14
    B.EQ    _m_expand_next_bit              // Already don't-care, skip

    // Try clearing this bit in mask → potential expansion
    BIC     w15, w12, w14                   // new_mask = mask & ~bit

    // Check if EXPANDED term (with w15 mask) covers any OFF
    MOV     w12, w15                         // Pass proposed mask to checker
    BL      _m_covers_any_off
    // Returns: w0 = 0 (no off covered) or 1 (covers an off)
    CMP     w0, #0
    B.NE    2f                               // Would cover off → can't expand

    // Safe to expand: w12 already = new mask, save it
    STR     w12, [x25, x10, LSL #2]          // Save new mask
    B       _m_expand_next_bit
2:
    // Reload original mask (expansion blocked)
    LDR     w12, [x25, x10, LSL #2]

_m_expand_next_bit:
    ADD     x13, x13, #1
    B       _m_expand_bit

_m_expand_next:
    ADD     x10, x10, #1
    B       _m_expand_loop

_m_expand_done:
    // ==========================================
    // IRREDUNDANT phase (greedy covering)
    // ==========================================

    // Copy current cover to work arrays
    ADRP    x0, m_work_val@PAGE
    ADD     x0, x0, m_work_val@PAGEOFF
    ADRP    x1, m_work_mask@PAGE
    ADD     x1, x1, m_work_mask@PAGEOFF
    ADRP    x6, m_work_cnt@PAGE
    ADD     x6, x6, m_work_cnt@PAGEOFF
    STR     x26, [x6]                       // work_cnt = cover_cnt

    MOV     x10, #0
_m_copy_work:
    CMP     x10, x26
    B.EQ    _m_copy_done
    LDR     w11, [x24, x10, LSL #2]
    STR     w11, [x0, x10, LSL #2]
    LDR     w11, [x25, x10, LSL #2]
    STR     w11, [x1, x10, LSL #2]
    ADD     x10, x10, #1
    B       _m_copy_work

_m_copy_done:
    // Clear selected and covered arrays
    ADRP    x2, m_selected@PAGE
    ADD     x2, x2, m_selected@PAGEOFF
    ADRP    x3, m_covered@PAGE
    ADD     x3, x3, m_covered@PAGEOFF

    MOV     x10, #0
_m_clear:
    CMP     x10, x26
    B.EQ    _m_clear_done
    STRB    wzr, [x2, x10]
    STRB    wzr, [x3, x10]
    ADD     x10, x10, #1
    B       _m_clear

_m_clear_done:
    // Clear covered array for minterms
    MOV     x10, #0
_m_clear_cov:
    CMP     x10, x20                        // on_count
    B.EQ    _m_greedy
    STRB    wzr, [x3, x10]
    ADD     x10, x10, #1
    B       _m_clear_cov

    // Greedy covering: pick implicant covering most uncovered minterms
_m_greedy:
    // Count uncovered minterms
    MOV     x4,  #0                         // uncovered count
    MOV     x5,  #0                         // minterm index

_m_count_uncovered:
    CMP     x5, x20
    B.EQ    _m_check_done

    LDRB    w6, [x3, x5]
    CMP     w6, #0
    B.NE    _m_cu_next
    ADD     x4, x4, #1
_m_cu_next:
    ADD     x5, x5, #1
    B       _m_count_uncovered

_m_check_done:
    CMP     x4, #0
    B.EQ    _m_irr_done                     // All covered

    // Find implicant with best coverage
    MOV     x5,  #-1                        // best_idx
    MOV     x6,  #-1                        // best_score

    MOV     x10, #0                         // impl_idx
_m_find_best:
    CMP     x10, x26
    B.EQ    _m_best_found

    // Skip already selected
    ADRP    x0, m_selected@PAGE
    ADD     x0, x0, m_selected@PAGEOFF
    LDRB    w0, [x0, x10]
    CMP     w0, #0
    B.NE    _m_fb_next

    // Count how many uncovered minterms this implicant covers
    LDR     w11, [x24, x10, LSL #2]         // value
    LDR     w12, [x25, x10, LSL #2]         // mask

    MOV     x7,  #0                         // score
    MOV     x8,  #0                         // mt_idx
_m_score_loop:
    CMP     x8, x20
    B.EQ    _m_score_done

    LDRB    w0, [x3, x8]                    // already covered?
    CMP     w0, #0
    B.NE    _m_sl_next

    LDR     w13, [x22, x8, LSL #2]          // minterm value
    // Check if implicant covers minterm: (mt & mask) == (val & mask)
    AND     w14, w13, w12
    AND     w15, w11, w12
    CMP     w14, w15
    B.NE    _m_sl_next
    ADD     x7, x7, #1

_m_sl_next:
    ADD     x8, x8, #1
    B       _m_score_loop

_m_score_done:
    CMP     x7, x6
    B.LE    _m_fb_next
    MOV     x5, x10                         // best_idx = current
    MOV     x6, x7                          // best_score = current score

_m_fb_next:
    ADD     x10, x10, #1
    B       _m_find_best

_m_best_found:
    CMP     x5, #-1
    B.EQ    _m_irr_done                     // No more choices

    // Select this implicant
    ADRP    x0, m_selected@PAGE
    ADD     x0, x0, m_selected@PAGEOFF
    MOV     w1, #1
    STRB    w1, [x0, x5]

    // Mark its covered minterms
    LDR     w11, [x24, x5, LSL #2]          // value
    LDR     w12, [x25, x5, LSL #2]          // mask

    MOV     x8, #0
_m_mark:
    CMP     x8, x20
    B.EQ    _m_greedy

    LDR     w13, [x22, x8, LSL #2]          // minterm
    AND     w14, w13, w12
    AND     w15, w11, w12
    CMP     w14, w15
    B.NE    _m_mark_next
    MOV     w1, #1
    STRB    w1, [x3, x8]                    // covered[mt] = 1

_m_mark_next:
    ADD     x8, x8, #1
    B       _m_mark

_m_irr_done:
    // Compact selected implicants into cover arrays
    MOV     x0,  #0                         // dst index
    MOV     x10, #0                         // src index
_m_compact:
    CMP     x10, x26
    B.EQ    _m_compact_done

    ADRP    x5, m_selected@PAGE
    ADD     x5, x5, m_selected@PAGEOFF
    LDRB    w5, [x5, x10]
    CMP     w5, #0
    B.EQ    _m_comp_next

    // Copy value and mask
    LDR     w11, [x24, x10, LSL #2]
    STR     w11, [x24, x0, LSL #2]
    LDR     w11, [x25, x10, LSL #2]
    STR     w11, [x25, x0, LSL #2]
    ADD     x0, x0, #1

_m_comp_next:
    ADD     x10, x10, #1
    B       _m_compact

_m_compact_done:
    // Compute cost = sum of popcount(mask) for all implicants
    MOV     x27, #0                         // cost = 0
    MOV     x10, #0
_m_cost_loop:
    CMP     x10, x0
    B.EQ    _m_cost_done
    LDR     w11, [x25, x10, LSL #2]         // mask
    BL      _m_popcount
    ADD     x27, x27, x12
    ADD     x10, x10, #1
    B       _m_cost_loop

_m_cost_done:
    MOV     x26, x0                         // new cover_cnt
    ADD     x28, x28, #1                    // next iteration
    B       _m_espresso_loop

_m_espresso_done:
    // ==========================================
    // GENERATE INFIX OUTPUT
    // ==========================================

    // Setup variable names (A, B, C, ...)
    ADRP    x0, m_var_names@PAGE
    ADD     x0, x0, m_var_names@PAGEOFF
    MOV     x1, #0
_m_init_names:
    CMP     x1, x19
    B.EQ    _m_names_done
    ADD     w2, w1, #'A'
    STRB    w2, [x0, x1]
    ADD     x1, x1, #1
    B       _m_init_names

_m_names_done:
    ADRP    x0, m_out_buf@PAGE
    ADD     x0, x0, m_out_buf@PAGEOFF
    MOV     x22, x0                        // output pointer

    MOV     x10, #0                         // implicant index
_m_build:
    CMP     x10, x26
    B.EQ    _m_build_done

    // Emit " | " before each implicant except the first
    CMP     x10, #0
    B.EQ    1f
    MOV     w2, #' '
    STRB    w2, [x22], #1
    MOV     w2, #'|'
    STRB    w2, [x22], #1
    MOV     w2, #' '
    STRB    w2, [x22], #1
1:
    LDR     w11, [x24, x10, LSL #2]         // value
    LDR     w12, [x25, x10, LSL #2]         // mask

    MOV     x15, #0                         // var index
    MOV     x16, #0                         // terms in this implicant

_m_emit_var:
    CMP     x15, x19
    B.EQ    _m_next_implicant

    MOV     w0, #1
    LSL     w0, w0, w15
    TST     w12, w0
    B.EQ    _m_evar_next                    // Don't care

    // Emit " & " before variable if not first in this term
    CMP     x16, #0
    B.EQ    1f
    MOV     w2, #' '
    STRB    w2, [x22], #1
    MOV     w2, #'&'
    STRB    w2, [x22], #1
    MOV     w2, #' '
    STRB    w2, [x22], #1
1:
    ADD     x16, x16, #1

    // Check if negated
    TST     w11, w0
    B.NE    1f
    MOV     w2, #'~'
    STRB    w2, [x22], #1
1:
    // Emit variable letter
    ADRP    x1, m_var_names@PAGE
    ADD     x1, x1, m_var_names@PAGEOFF
    LDRB    w2, [x1, x15]
    STRB    w2, [x22], #1

_m_evar_next:
    ADD     x15, x15, #1
    B       _m_emit_var

_m_next_implicant:
    ADD     x10, x10, #1
    B       _m_build

_m_build_done:
    MOV     w2, #'\n'
    STRB    w2, [x22], #1

_m_output:
    ADRP    x1, m_out_buf@PAGE
    ADD     x1, x1, m_out_buf@PAGEOFF
    SUB     x2, x22, x1
    MOV     x0, #STDOUT
    LDR     x16, =SYS_WRITE
    SVC     #0x80

    B       _m_exit_ok

_m_output_zero:
    // Output "0\n"
    MOV     x0, #STDOUT
    ADRP    x1, msg_zero@PAGE
    ADD     x1, x1, msg_zero@PAGEOFF
    MOV     x2, #2
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    B       _m_exit_ok

_m_output_one:
    // Output "1\n"
    MOV     x0, #STDOUT
    ADRP    x1, msg_one@PAGE
    ADD     x1, x1, msg_one@PAGEOFF
    MOV     x2, #2
    LDR     x16, =SYS_WRITE
    SVC     #0x80
    B       _m_exit_ok

_m_exit_ok:
    MOV     x0, #0
    LDP     fp, lr, [sp], #16
    RET

// ==========================================
// COVERS ANY OFF? Check if (value, mask)
// covers any OFF-set minterm
// Input:  w11=value, w12=mask, x19=N, x23=off_set, x21=off_count
// Output: w0 = 0 (no), 1 (yes)
// ==========================================

_m_covers_any_off:
    MOV     x0, #0                          // Default: no off covered
    STP     x1, x2, [sp, #-16]!

    ADRP    x2, m_off_count@PAGE
    ADD     x2, x2, m_off_count@PAGEOFF
    LDR     x2, [x2]                        // x2 = off_count

    MOV     x1, #0                          // index
_m_cao_loop:
    CMP     x1, x2
    B.EQ    _m_cao_done_real

    LDR     w9, [x23, x1, LSL #2]           // OFF minterm
    AND     w3, w9, w12                     // (off_min & mask)
    AND     w4, w11, w12                     // (value & mask)
    CMP     w3, w4
    B.NE    _m_cao_next

    MOV     x0, #1                          // Found a covered OFF
    B       _m_cao_done_real

_m_cao_next:
    ADD     x1, x1, #1
    B       _m_cao_loop

_m_cao_done_real:
    LDP     x1, x2, [sp], #16
    RET

// ==========================================
// POPCOUNT: count 1 bits in w11
// Input:  w11
// Output: x12 = popcount
// ==========================================

_m_popcount:
    MOV     x12, #0
    MOV     w13, w11
_m_pc_loop:
    CMP     w13, #0
    B.EQ    _m_pc_done
    SUB     w14, w13, #1
    AND     w13, w13, w14
    ADD     x12, x12, #1
    B       _m_pc_loop
_m_pc_done:
    RET

// Popcount version returning in x2
_m_popcount_w:
    STP     x12, lr, [sp, #-16]!
    MOV     w11, w13
    BL      _m_popcount
    MOV     x2, x12
    LDP     x12, lr, [sp], #16
    RET

// ==========================================
// DATA
// ==========================================
.section __TEXT, __const
msg_zero:
    .asciz "0\n"
msg_one:
    .asciz "1\n"
