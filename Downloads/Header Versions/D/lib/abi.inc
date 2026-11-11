; Liberated Peep: calling-convention glue shared by every .asm file.
; Assembles for System V (Linux, BSD, macOS-style) and Microsoft x64 (-DWIN64).
default rel
bits 64

%ifdef WIN64
    %define A1 rcx
    %define A2 rdx
    %define A3 r8
    %define A4 r9
    %define IN5 qword [rbp + 48]        ; 5th/6th argument, read right after ARGS
    %define IN6 qword [rbp + 56]
%else
    %define A1 rdi
    %define A2 rsi
    %define A3 rdx
    %define A4 rcx
    %define IN5 r8
    %define IN6 r9
%endif

; FUNC name, local_bytes : every function saves every callee-saved register of
; both ABIs, keeps 16-byte alignment and reserves the Win64 shadow space, so one
; body is correct for both and can call a callback either way.
; Locals start at [rsp + 32] == [rbp - 64 - round16(local_bytes)].
%macro PROLOGUE 1
    push rbp
    mov  rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub  rsp, 32 + (((%1) + 15) & ~15) + 8
%endmacro
%macro FUNC 2                     ; exported
%ifdef WIN64
    global %1
%else
    global %1:function
%endif
%1:
    PROLOGUE %2
%endmacro
%macro FUNCL 2                    ; file-local (reached through a pointer)
%1:
    PROLOGUE %2
%endmacro

%macro RET_ 0
    lea  rsp, [rbp - 56]
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rdi
    pop  rsi
    pop  rbx
    pop  rbp
    ret
%endmacro

%macro ARGS 1-4
    mov %1, A1
%if %0 > 1
    mov %2, A2
%endif
%if %0 > 2
    mov %3, A3
%endif
%if %0 > 3
    mov %4, A4
%endif
%endmacro
