CC = gcc
CFLAGS = -nostdlib -fno-stack-protector -g -s
PYTHON = python3

SRC_DIR = src_trans
BIN_DIR = bin

ASSEMBLER = $(SRC_DIR)/assembler.py
PAYLOAD_ASM = $(SRC_DIR)/payload.asm
PAYLOAD_INC = $(SRC_DIR)/payload.inc
MAIN_SRC = $(SRC_DIR)/main.S
TARGET = $(BIN_DIR)/builder

.PHONY: all clean tests

all: $(TARGET)

$(TARGET): $(PAYLOAD_INC) $(MAIN_SRC) | $(BIN_DIR)
	$(CC) $(CFLAGS) $(MAIN_SRC) -o $(TARGET)

$(PAYLOAD_INC): $(PAYLOAD_ASM) $(ASSEMBLER)
	$(PYTHON) $(ASSEMBLER) $(PAYLOAD_ASM) $(PAYLOAD_INC)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

tests: $(TARGET)
	rm -rf generations
	mkdir generations
	cp $(TARGET) generations/gen1
	./run_test.sh

clean:
	rm -f $(PAYLOAD_INC)
	rm -rf $(BIN_DIR)
	rm -rf generations
