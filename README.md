# Polymorphic_Engine

**Disclaimer:** This polymorphic engine was made as a part of an academic project for the Architecture of Computer Systems course at UCU.

You can read full report [here](https://www.overleaf.com/read/fxzmcktnmmgq#62d9b6)

## Build Instructions

A `Makefile` is provided in the root directory to simplify assembling, compiling, and testing the polymorphic engine.

### Prerequisites
- `gcc`
- `python3`

### Building the Project
To assemble the target payload (`payload.asm` -> `payload.inc`) and compile the `builder` executable, run:
```bash
make
```
This will compile the output to `bin/builder`.

### Running Tests
To build the project, set up the `generations` directory, and automatically run the generational 50-iteration test, run:
```bash
make tests
```

### Cleaning Up
To remove all generated object files, the `bin` directory, and test generation folders, run:
```bash
make clean
```
