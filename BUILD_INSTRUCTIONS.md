# Mozilla AMO Reviewer Build Instructions

This extension uses Vite, React, TypeScript, and Rust WebAssembly.

## Requirements
- Node.js (v18 or higher recommended)
- npm (Node Package Manager)
- Rust and Cargo (https://rustup.rs/)
- wasm-pack (`cargo install wasm-pack`)

## Build Steps

1. Clone or extract this source code. If cloning from git, ensure you pull the submodules:
   `git clone --recursive https://github.com/saifmukhtar/kinetic-client.git`
   If you extracted the zip, the submodules (`kinetic` and `chiavdf` directories) are already included.

2. Install JavaScript dependencies:
   `npm install`

3. Compile the WebAssembly module:
   `npm run build:wasm`

4. Build the Firefox extension:
   `npm run build:firefox`

5. The final built extension will be located in the `dist` directory. You can load it into Firefox by navigating to `about:debugging#/runtime/this-firefox` and clicking "Load Temporary Add-on", then selecting the `manifest.json` file inside the `dist` folder.
