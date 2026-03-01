.intel_syntax noprefix

.data
    my_str: .string "The value of rax: %d\n" 

.section .text
.globl main

main:
	# syscall to mprotect to allow write to read-only .text section
    mov rax, 10
    lea rdi, [rip + Start]
    and rdi, -4096
    mov rsi, 4096
    mov rdx, 7
    syscall
    
    lea rax, [rip + Start]
	mov rcx, 0x11223344

Decrypt:
	xor byte ptr [rax], 0x55
	inc rax
    nop
    nop
    nop
	loop Decrypt

    call Start

Start:
	# encoded "mov eax 0x15" and "ret" with key=0x12
    .byte 0xCA, 0xFE, 0xBA, 0xBE
