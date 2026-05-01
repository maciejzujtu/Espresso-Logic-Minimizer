// parser.s
.global _parse_buffer
.section __TEXT, __text

_parse_buffer:
    STP     x19, x20, [sp, #-48]!   // Rezerwujemy więcej miejsca
    STP     x21, x22, [sp, #16]
    STP     x23, lr,  [sp, #32]

    MOV     x19, x0                 // x19 = Infix input (buffer)
    ADD     x20, x0, x1             // x20 = Koniec inputu
    
    ADRP    x21, rpn_output@PAGE
    ADD     x21, x21, rpn_output@PAGEOFF // x21 = Wskaźnik wyjścia RPN
    
    ADRP    x22, op_stack@PAGE
    ADD     x22, x22, op_stack@PAGEOFF   // x22 = Wskaźnik stosu operatorów

_main_loop:
    CMP     x19, x20
    B.GE    _flush_operators
    LDRB    w23, [x19], #1          // Pobierz znak

    // 1. Jeśli Litera (A-D) -> Od razu na wyjście RPN
    CMP     w23, #'A'
    B.LT    _not_letter
    CMP     w23, #'Z'
    B.GT    _not_letter
    STRB    w23, [x21], #1
    B       _main_loop

_not_letter:
    // 2. Jeśli Nawias Otwierający '(' -> Na stos operatorów
    CMP     w23, #'('
    B.NE    _not_open_paren
    STRB    w23, [x22], #1
    B       _main_loop

_not_open_paren:
    // 3. Jeśli Nawias Zamykający ')' -> Przerzuć wszystko do '(' na wyjście
    CMP     w23, #')'
    B.NE    _check_operators
_pop_until_paren:
    SUB     x22, x22, #1
    LDRB    w24, [x22]
    CMP     w24, #'('
    B.EQ    _main_loop              // Znaleźliśmy '(', wracamy do pętli
    STRB    w24, [x21], #1          // Przerzuć operator na wyjście
    B       _pop_until_paren

_check_operators:
    // 4. Jeśli Operator (& lub |)
    // Uproszczenie: & (AND) ma wyższy priorytet niż | (OR)
    CMP     w23, #'&'
    B.EQ    _handle_and
    CMP     w23, #'|'
    B.EQ    _handle_or
    B       _main_loop              // Ignoruj spacje i resztę

_handle_and:
    // AND ma najwyższy priorytet, po prostu wrzuć na stos
    STRB    w23, [x22], #1
    B       _main_loop

_handle_or:
    // Przed wrzuceniem OR, sprawdź czy na stosie jest AND (wyższy priorytet)
    // Jeśli tak - zdejmij AND na wyjście
    CBZ     x22, _push_or           // Stos pusty -> wrzuć OR
    LDRB    w24, [x22, #-1]!        // Podejrzyj szczyt
    CMP     w24, #'&'
    B.NE    _push_or_fix_ptr
    STRB    w24, [x21], #1          // Przerzuć AND na wyjście
    B       _push_or
_push_or_fix_ptr:
    ADD     x22, x22, #1            // Przywróć wskaźnik jeśli nie zdjęliśmy
_push_or:
    MOV     w24, #'|'
    STRB    w24, [x22], #1
    B       _main_loop

_flush_operators:
    // Na końcu pliku, opróżnij stos operatorów na wyjście
    ADRP    x24, op_stack@PAGE
    ADD     x24, x24, op_stack@PAGEOFF
_flush_loop:
    CMP     x22, x24
    B.EQ    _print_rpn
    LDRB    w25, [x22, #-1]!
    CMP     w25, #'('               // Ignoruj zbędne nawiasy
    B.EQ    _flush_loop
    STRB    w25, [x21], #1
    B       _flush_loop

_print_rpn:
    // Tutaj użyjemy Twojego starego kodu z SYS_WRITE, 
    // żeby zobaczyć czy RPN jest poprawne
    ADRP    x1, rpn_output@PAGE
    ADD     x1, x1, rpn_output@PAGEOFF
    SUB     x2, x21, x1             // Długość = obecny_wskaźnik - start
    MOV     x0, #1                  // STDOUT
    LDR     x16, =0x2000004         // SYS_WRITE
    SVC     #0x80

    LDP     x23, lr,  [sp, #32]
    LDP     x21, x22, [sp, #16]
    LDP     x19, x20, [sp], #48
    RET