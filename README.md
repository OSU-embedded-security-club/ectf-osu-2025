# OSU Satellite TV for MITRE eCTF 2025

This repo contains all the code and documentation for team scriptohio from The Ohio State University in [MITRE's eCTF 2025](https://rules.ectf.mitre.org/2025/index.html).

Highlights of our design:

- 🔑 **Strong cryptography**
    - 🌲 Our _binary hash key derivation tree_ efficiently compresses unique keys per timestamp to create a subscription over a time interval 🕐
    - 💃 The [Salsa20](https://en.wikipedia.org/wiki/Salsa20) post-quantum stream cipher is used for lightning quick symmetric encryption and decryption
    - 📝 All frames are signed and verified with [Ed25519](https://en.wikipedia.org/wiki/EdDSA#Ed25519) to ensure decoders only read frames from the encoder they came from
- ⚡ **Written in Zig**
    - 📦 Expansive standard library which includes everything a programmer might need, from string manipulation to secure cryptography
    - 🧪 Unit tests built in, allowing for critical sections to have their correctness verified
    - 🚫 Memory safety protections against common issues like indexing out of bounds, double free, integer overflows, and more
    - 🚧 Build system with incredible interoperability with C code. We still use the MSDK, and no HAL rewrites in sight 👀

## Layout 🌎

- `decoder` - Firmware for the decoder
- `design` - Host design including encoder
- `docs` - Documentation on the system design and how it protects
- `tools` - MITRE provided Host tools to interact with the decoder (Not modified)

## Documentation 📖

The design document is available to read as a PDF here:

- [Design PDF](docs/design.pdf)
