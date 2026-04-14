import random
import sys
import os

INSTRUCTION_OPERAND_SIZES = {
    "MOV_REG_IMM": 5,    
    "MOV_REG_IMM64": 9,
    "SYSCALL": 0,
    "UNUSED": 0,
    "ALU_REG_IMM": 5,
    "JNE_REL8": 1,
    "LEA_RSI_REL": 4,
    "PUSH_IMM32": 4,
    "LEA_RDI_REL": 4,
    "DATA_8": 8,
    "MOV_REG_REG": 2,
    "MOV_MEM_REG": 2,
    "MOV_REG_MEM": 2,
    "MOV_REG_IMM8": 2,
    "INC_REG": 1,
    "DEC_REG": 1,
    "CMP_REG_IMM8": 2,
    "CMP_REG_REG": 2,
    "JMP_REL8": 1,
    "JE_REL8": 1,
    "JL_REL8": 1,
    "JGE_REL8": 1,
    "JNC_REL8": 1,
    "PUSH_REG": 1,
    "POP_REG": 1,
    "XOR_REG_REG": 2,
    "RDRAND_REG": 1,
    "DIV_REG": 1,
    "IMUL_REG_IMM8": 2,
    "AND_REG_IMM8": 2,
    "ADD_REG_IMM8": 2,
    "SUB_REG_REG": 2,
    "ADD_REG_REG": 2,
    "MOV_BYTE_MEM_REG": 2,
    "MOV_REG_BYTE_MEM": 2,
    "LEA_REG_RIP_REL": 5,
    "JNOP": 0,
    "ADD_REG_IMM32": 5
}

INSTRUCTIONS = {}

REGISTERS = {
    "rax": 0x00, "rcx": 0x01, "rdx": 0x02, "rbx": 0x03,
    "rsp": 0x04, "rbp": 0x05, "rsi": 0x06, "rdi": 0x07,
    "r8":  0x08, "r9":  0x09, "r10": 0x0A, "r11": 0x0B,
    "r12": 0x0C, "r13": 0x0D, "r14": 0x0E, "r15": 0x0F
}

BRANCH_INSTRUCTIONS = ["JNE_REL8", "JMP_REL8", "JE_REL8", "JL_REL8", "JGE_REL8", "JNC_REL8"]

def x86_len(inst, operands):
    def reg_rex(op):
        val = parse_operand(op)
        return 1 if isinstance(val, int) and val > 7 else 0
        
    if inst == ".byte": return len(operands)
    elif inst == "SYSCALL": return 2
    elif inst == "JNOP": return 1
    elif inst == "MOV_REG_IMM": return 7
    elif inst == "MOV_REG_IMM64": return 10
    elif inst == "ALU_REG_IMM": return 7
    elif inst == "ADD_REG_IMM32": return 7
    elif inst in BRANCH_INSTRUCTIONS: return 2
    elif inst in ["LEA_RSI_REL", "LEA_RDI_REL"]: return 7
    elif inst == "PUSH_IMM32": return 5
    elif inst == "DATA_8": return 8
    elif inst in ["MOV_REG_REG", "XOR_REG_REG", "SUB_REG_REG", "ADD_REG_REG", "CMP_REG_REG", "MOV_MEM_REG", "MOV_BYTE_MEM_REG", "MOV_REG_MEM"]:
        rex = 1  # 0x48 base REX usually used
        return rex + 1 + 1 # rex + op + modrm
    elif inst == "MOV_REG_BYTE_MEM":
        return 1 + 2 + 1 # REX + 0F B6 + ModRM
    elif inst == "RDRAND_REG":
        return 1 + 2 + 1 # REX + 0F C7 + ModRM
    elif inst in ["INC_REG", "DEC_REG", "DIV_REG"]:
        return 1 + 1 + 1
    elif inst in ["PUSH_REG", "POP_REG"]:
        return (1 if reg_rex(operands[0]) else 0) + 1
    elif inst == "MOV_REG_IMM8":
        return 1 + 1 + 1 + 4   # REX + 0xC7 + ModRM + imm32
    elif inst in ["CMP_REG_IMM8", "AND_REG_IMM8", "ADD_REG_IMM8"]:
        return 1 + 1 + 1 + 1
    elif inst in ["IMUL_REG_IMM8"]:
        return 1 + 1 + 1 + 1
    elif inst == "LEA_REG_RIP_REL":
        return 1 + 1 + 1 + 4
    return 0

def parse_operand(op, is_branch=False):
    op_clean = op.strip('[]')
    if op_clean in REGISTERS:
        return REGISTERS[op_clean]
    try:
        if op.startswith("0x"):
            return int(op, 16)
        return int(op)
    except ValueError:
        return op

def generate_aliases():
    global INSTRUCTIONS
    start_alias = 0x10
    for inst in INSTRUCTION_OPERAND_SIZES.keys():
        INSTRUCTIONS[inst] = [start_alias, start_alias+1, start_alias+2]
        start_alias += 3

generate_aliases()

def pass1(lines):
    offset = 0
    labels = {}
    for line in lines:
        line = line.split("#")[0].strip()
        if not line or line.startswith('#'):
            continue
        if line.endswith(':'):
            labels[line[:-1]] = offset
            continue
            
        parts = line.replace(',', ' ').split()
        if not parts: continue
        inst = parts[0]
            
        if inst == ".byte":
            offset += len(parts) - 1
            continue

        if inst not in INSTRUCTION_OPERAND_SIZES:
            print(f"Unknown instruction: {inst}")
            sys.exit(1)
            
        size = x86_len(inst, parts[1:])
        offset += size
    return labels

def pass2(lines, labels):
    output = []
    offset = 0
    for line in lines:
        line = line.split("#")[0].strip()
        if not line or line.startswith('#') or line.endswith(':'):
            continue
            
        parts = line.replace(',', ' ').split()
        inst = parts[0]
        operands = parts[1:]
            
        if inst == ".byte":
            byte_strs = []
            for op in operands:
                val = parse_operand(op)
                byte_strs.append(f"0x{val & 0xFF:02X}")
            output.append(f"    .byte {', '.join(byte_strs)}  # {line}")
            offset += len(operands)
            continue

        alias = random.choice(INSTRUCTIONS[inst])
        
        byte_strs = [f"0x{alias:02X}"]
        
        if inst in BRANCH_INSTRUCTIONS:
            target = operands[0]
            if target in labels:
                rel8 = labels[target] - (offset + x86_len(inst, operands))
                if rel8 < -128 or rel8 > 127:
                    print(f"Error: Branch target {target} out of range ({rel8})")
                    sys.exit(1)
                byte_strs.append(f"0x{(rel8 & 0xFF):02X}")
            else:
                val = parse_operand(target, True)
                if isinstance(val, int):
                    byte_strs.append(f"0x{(val & 0xFF):02X}")
                else:
                    print(f"Error: Unknown label {target}")
                    sys.exit(1)
        elif inst in ["LEA_REG_RIP_REL", "LEA_RSI_REL", "LEA_RDI_REL"]:
            target = operands[0] if inst != "LEA_REG_RIP_REL" else operands[1]
            if inst == "LEA_REG_RIP_REL":
                reg = parse_operand(operands[0])
                byte_strs.append(f"0x{reg & 0xFF:02X}")
            if target in labels:
                rel32 = labels[target] - (offset + x86_len(inst, operands))
                if rel32 < 0: rel32 = rel32 & 0xFFFFFFFF
                byte_strs.extend([f"0x{(rel32 >> (8*j)) & 0xFF:02X}" for j in range(4)])
            else:
                val = parse_operand(target)
                if isinstance(val, int):
                    val = val & 0xFFFFFFFF
                    byte_strs.extend([f"0x{(val >> (8*j)) & 0xFF:02X}" for j in range(4)])
                else:
                    print(f"Error: Unknown label {target}")
                    sys.exit(1)
        else:
            for i, op in enumerate(operands):
                val = parse_operand(op)
                if isinstance(val, int):
                    if val < 0: val = val & 0xFFFFFFFFFFFFFFFF
                    if inst in ["LEA_REG_RIP_REL", "LEA_RSI_REL", "LEA_RDI_REL"] and i == 1:
                        byte_strs.extend([f"0x{(val >> (8*j)) & 0xFF:02X}" for j in range(4)])
                    elif inst == "PUSH_IMM32" and i == 0:
                        byte_strs.extend([f"0x{(val >> (8*j)) & 0xFF:02X}" for j in range(4)])
                    elif inst == "MOV_REG_IMM64" and i == 1:
                        byte_strs.extend([f"0x{(val >> (8*j)) & 0xFF:02X}" for j in range(8)])
                    elif inst in ["MOV_REG_IMM", "ALU_REG_IMM", "ADD_REG_IMM32"] and i == 0:
                        byte_strs.append(f"0x{val & 0xFF:02X}")
                    elif inst in ["MOV_REG_IMM", "ALU_REG_IMM", "ADD_REG_IMM32"] and i == 1:
                        byte_strs.extend([f"0x{(val >> (8*j)) & 0xFF:02X}" for j in range(4)])
                    else:
                        byte_strs.append(f"0x{val & 0xFF:02X}")
                else:
                    byte_strs.append(f"{val}")
                    
        output.append(f"    .byte {', '.join(byte_strs)}  # {line}")
        offset += x86_len(inst, operands)
        
    return output

def assemble(input_file, output_file):
    with open(input_file, 'r') as f:
        lines = f.readlines()
        
    labels = pass1(lines)
    out_lines = pass2(lines, labels)
        
    with open(output_file, 'w') as f:
        f.write("custom_payload:\n")
        f.write("\n".join(out_lines))
        f.write("\ncustom_payload_end:\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python assembler.py <input.asm> <output.inc>")
        sys.exit(1)
    
    assemble(sys.argv[1], sys.argv[2])
    print(f"Successfully assembled {sys.argv[1]} -> {sys.argv[2]}")
