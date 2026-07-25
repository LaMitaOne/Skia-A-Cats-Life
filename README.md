# Skia-A-Cats-Life
A 2.5D isometric game prototype built entirely with Skia4Delphi.   
   
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/Skia-A-Cats-Life)
     
<img width="510" height="314" alt="f32cec6d-5d9a-4b1f-ad84-2723ab45409e" src="https://github.com/user-attachments/assets/243e1c91-72a0-4c51-b988-792c64e11d31" />
    
Sample Video: [https://www.youtube.com/watch?v=mePkXrbPfJg](https://youtu.be/J8gzBo9eu04)    
    
Control a cat in a tiny apartment, push glasses off tables, and chase a mouse. It's not a perfect engine, sure still lot to do and problems to find, the z-order isn't always correct, but it demonstrates core isometric mechanics without the bloat of a full game engine. Enjoy! :D

🎮 Gameplay Features

- Center-Based Coordinates: A grid system inspired by OpenTTD/Flare RPG where objects are placed by their exact center, making multi-tile furniture placement easy.
- Procedural 3D Iso-Boxes: Furniture is drawn procedurally as 3D boxes with perfect grid alignment, dynamic lighting (top/left/right faces), and Z-axis height.
- X-Ray Vision: Objects become semi-transparent when the cat walks behind them, so you never lose sight of your character.  
- Physics & Destruction: Bump into glasses on tables to knock them off. They fall, hit the ground, and shatter into glowing particles.
- Simple AI: A wandering mouse roams the apartment. Catch it, and it teleports to a new spot.
- Smooth Z-Interpolation: The cat smoothly steps up onto furniture and falls down when walking off edges.

🕹️ Controls

- Move: W/A/S/D or Arrow Keys
- Move (Click-to-Move): Left-Click anywhere on the floor 

🛠️ Technical Details

- Renderer: Pure Skia Canvas (No Game Engine, no FMX shapes). Everything is drawn using paths, masks, and blurs.
- Threading: Physics and AI run on a background thread for consistent FPS, synchronized safely with the main rendering thread.
- Axis-Separated Collision: X and Y movements are checked independently, allowing the cat to "slide" smoothly along walls instead of getting stuck.
- Painter's Algorithm: Objects are dynamically sorted by isometric depth (GridX + GridY + Z) before rendering, ensuring correct overlapping.
- Single-File Architecture: The complete isometric engine, including rendering and logic, is contained in one highly commented file.

📦 What's Inside

- SkiaCatsLife.pas: The complete 2.5D engine in a single file.
- Sample project and executable included.

🚀 Getting Started

Open the project in RAD Studio (Delphi).
Ensure you have the Skia4Delphi library installed.
Run and play!

---- Latest Changes

v 0.1: Initial Release

- Implemented center-based isometric grid system and procedural tile rendering.    
- Added 3D iso-box drawing for furniture (Sofa, Table, Bed, Wardrobe, etc.).     
- Added dynamic X-Ray transparency for objects obstructing the cat.     
- Implemented Axis-separated collision detection allowing sliding along walls.     
- Added interactive physics objects (Glasses fall and shatter into particles).     
- Added wandering mouse AI with catch-and-teleport mechanic.     

License

MIT License - Do whatever you want with it. Credits appreciated but not required.    

     
🎮 Skia4Delphi Games (each one file, no ext engine):    
   2D Platformer https://github.com/LaMitaOne/Skia_PlatformerGame    
   C&C style 2.5D isometric rts https://github.com/LaMitaOne/Skia-RTS-Game   
   Tetris clone https://github.com/LaMitaOne/Skiatris    
   2D side-scrolling space shooter https://github.com/LaMitaOne/SkiaStarPatrols    
   Lemmings/Worms/Portal/Touch 2D hybrid https://github.com/LaMitaOne/SkiaLemmings       
     
🎮 Game components FMX:    
   MRX Gamepad Core https://github.com/LaMitaOne/MRX-Gamepad-Core     
