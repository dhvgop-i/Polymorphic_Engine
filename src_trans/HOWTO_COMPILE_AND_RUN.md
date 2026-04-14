# Polymorphic Engine: Compile and Run Guide

This document explains the steps to write a payload, assemble it into the custom Instruction Set Architecture (ISA) format, compile the polymorphic engine (builder), and finally run it.

## 1. Assemble the Payload
The engine relies on a custom Python two-pass assembler that translates pseudo-assembly instructions into a structured byte array (`payload.inc`). 

Write your code in a `.asm` file (e.g., `test_whole_payload.asm` or `payload.asm`) and use the assembler to generate the `.inc` file which is directly `#include`'d by `main.S`.

From the workspace root, run:
```bash
python3 src_trans/assembler.py src_trans/test_whole_payload.asm src_trans/payload.inc
```

## 2. Compile the Builder Engine
The builder is written entirely in x86-64 assembly in `src_trans/main.S`. It needs to be compiled natively without the C standard library to ensure the resulting ELF works nicely with the embedded file self-replication/patching routines.

Run the following GCC command from the workspace root:
```bash
mkdir -p bin
gcc -nostdlib -fno-stack-protector -g src_trans/main.S -o bin/builder
```

## 3. Execute the Builder
Running the compiled `builder` executable will immediately:
1. **JIT compilation:** Decode your custom ISA bytes into valid x86-64 opcodes in a dynamically mapped (`mmap`) executable memory region.
2. **Execution:** Seamlessly execute your payload natively.
3. **Mutation & Replication:** It extracts its own ELF bytes from disk, mutates the instruction alias map randomly, embeds the updated map, and generates a standalone executable binary payload dynamically (dropped in your directory with a random 8-character name like `gYwBqZnX`).

Run it using:
```bash
./bin/builder
```

## 4. Verify Execution
If you're testing arithmetic and loops (using `test_whole_payload.asm`), the result is deliberately returned as the program's exit code. Verify it with:
```bash
echo $?
# Should output 42
```
