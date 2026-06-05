# 🐦 Flappy Bird: The x86 Assembly Chronicles

Welcome to the ultimate retro experiment. This repository contains **two distinct flavors** of the classic game *Flappy Bird*, both powered by raw x86 assembly processing.

Whether you prefer the charm of an 80×25 character console or the smooth rendering of a hardware-accelerated Win32 window, we've got your FPU (Floating Point Unit) covered.

---

# 🎮 The Dual Engine Architecture

This project splits into two completely separate implementations, highlighting different eras and techniques of assembly development.

| Feature                  | 📟 Console Edition                           | 🖼️ Win32 GUI Edition                         |
| ------------------------ | -------------------------------------------- | --------------------------------------------- |
| **Language**             | 100% Pure x86 Assembly                       | Hybrid C++ & Inline x86 Assembly              |
| **Assembler / Compiler** | MASM (`ml.exe`)                              | Microsoft Visual C++ (MSVC)                   |
| **Graphics Engine**      | Double-buffered Console API (`screenChars`)  | GDI+ with double-buffered `BitBlt`            |
| **Libraries**            | `Irvine32.lib`, `kernel32.lib`, `user32.lib` | `Gdiplus.lib`, `user32.lib`, `gdi32.lib`      |
| **Performance Target**   | ~30 FPS (33ms tick rate)                     | ~60 FPS (16ms tick rate)                      |
| **Visual Assets**        | Custom Extended ASCII (`█`, `▓`, `░`)        | Pre-scaled PNG sprites (`bg.png`, `bird.png`) |

---

# 🔬 Core Features & Assembly Mechanics

## 1. Pure Assembly Console Edition

This version acts as a bare-metal style simulation within the Windows terminal.

### ⚙️ FPU Physics Control

Real-time gravity (`0.18` per frame) and vertical velocity calculations are handled completely through the x86 FPU stack using instructions such as:

```asm
fld
fadd
fcomp
```

### 🖥️ Flicker-Free Double Buffering

Characters and colors are written into local software buffers:

* `screenChars`
* `screenColors`

The entire frame is then flushed at once through the Windows Console API to eliminate flickering.

### 🧱 Procedural Pipe Architect

Dynamically shifts arrays of up to 10 simultaneous pipe structures while clearing off-screen elements using efficient memory operations:

```asm
rep movsb
```

---

## 2. Hybrid Win32 GDI+ Edition

This version combines standard Windows window management with ultra-optimized assembly critical paths.

### 🚀 Inline Math Acceleration

Core gameplay loops—specifically:

* `UpdatePhysicsAsm`
* `CheckCollisionAsm`

are implemented entirely using inline `__asm` blocks.

### 🎨 Visual Polish

Uses GDI+ nearest-neighbor interpolation to preserve crisp retro pixel-art edges.

### 🔄 Dynamic Transformations

Features procedural matrix rotation using `RotateTransform`, allowing the bird sprite to tilt dynamically based on vertical velocity.

---

# 🕹️ Controls

Both games use the same arcade-accurate control layout.

| Key        | Action                            |
| ---------- | --------------------------------- |
| `SPACEBAR` | Start the game (Menu)             |
| `SPACEBAR` | Flap upward during gameplay       |
| `SPACEBAR` | Restart instantly after Game Over |

---

# 🛠️ Compilation & Running

## Prerequisites

* Visual Studio with **Desktop Development with C++** workload installed
* Irvine32 Library *(required only for the Console Edition)*

---

## Running the Graphical Version

1. Place the following files in the same directory as the compiled `.exe`:

   * `bg.png`
   * `bird.png`

2. Launch the application.

If the image assets are missing, the engine automatically falls back to rendering a classic yellow vector-ellipse bird.

---

# 📝 Technical Design Note — Collision Hitboxes

The collision engine leverages strict FPU comparisons to check bounding boxes.

* In the **Console Edition**, the bird occupies a `1×1` text-cell grid.
* In the **Win32 Edition**, the hitbox scales to `44×44` pixels to compensate for sprite texture padding.

This guarantees mechanically fair and visually accurate collision behavior.
