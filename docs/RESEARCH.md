# Desktop Destroyer research and product translation

## What the original was

Desktop Destroyer, also reported under the original name Desktop Games, was a tiny 1999 Windows desktop toy. Its defining illusion was full-screen interaction with a static image of the user's desktop: the operating system and files were never actually damaged.

The recognizable palette contained nine tools:

1. Hammer
2. Chain-saw
3. Machine gun
4. Flame-thrower
5. Color-thrower
6. Phaser
7. Stamp
8. Termites
9. Washing

The controls were intentionally immediate: number keys selected tools and the mouse used them. The key experiential ingredients were persistent marks, tools that felt materially different, autonomous termites, and a way to clean or reset the surface.

## Sources reviewed

- [La República retrospective](https://larepublica.pe/tecnologia/actualidad/2023/12/21/que-paso-con-desktop-destroyer-el-programa-con-el-que-podias-romper-la-pantalla-de-tu-pc-2049222) — history, 1999 attribution, static-desktop illusion, and representative tools.
- [Desktop Destroyer remake on itch.io](https://ujugames.itch.io/desktop-destroyer) — the preserved `1`–`9` selection and mouse interaction model.
- [Casual Desktop Game on Steam](https://store.steampowered.com/app/1001860/Casual_Desktop_Game/) — evidence that later revivals retained the screen-destruction sandbox, multiple tools, cleaning, alternative backgrounds, and autonomous entities.
- [Casual Desktop Game project page](https://danielbrendel.itch.io/casual-desktop-game) — current revival feature set and interaction reference.

## Translation into a modern Mac app

The replica keeps the original interaction loop but changes the implementation and presentation:

- ScreenCaptureKit replaces legacy desktop screenshot APIs and excludes this app from the captured background.
- A native AppKit window, system typography, materials, SF Symbols, full-screen support, and keyboard shortcuts make it feel at home on macOS.
- The permanent-looking damage is an in-memory `RGBA16Float` texture. A bounded Metal compute dispatch edits only the pixels around each interaction.
- Hammer cracks, saw cuts, bullet holes, soot, paint, energy burns, seals, termite bites, and washing combine generated original artwork with procedural breakup rather than copied game art.
- Up to 8,192 debris, spark, ember, energy, and foam particles are simulated in a GPU buffer and drawn from a purpose-built VFX atlas.
- Termite movement is lightweight CPU behavior; generated walk-cycle sprites, drawing, and accumulated chewing are Metal accelerated.
- Reset clears simulation state and the destruction texture. Nothing writes to the desktop, files, or captured image.

## Deliberate scope

The first version focuses on a polished, faithful destruction toy. Workshop mods, combat units, blueprints, and community content belong to later revivals rather than the essential 1999 loop, so they are not part of this replica.
