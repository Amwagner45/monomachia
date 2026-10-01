# Credits

The art in `game/assets` comes from free packs by Quaternius. Every pack is under the **CC0 1.0 Universal** public domain dedication (https://creativecommons.org/publicdomain/zero/1.0/): free for any use, commercial included, with no credit required. We credit Quaternius anyway.

Models and animations by **Quaternius** (https://quaternius.com, https://www.patreon.com/quaternius).

| Files | Pack | Source | Licence |
|---|---|---|---|
| `quaternius/animations/UAL1_Standard.glb` | Universal Animation Library, Standard (free) tier | https://quaternius.com | CC0 1.0 (`License.txt` in the pack) |
| `quaternius/animations/UAL2_Standard.glb` | Universal Animation Library 2, Standard tier | https://quaternius.com | CC0 1.0 (`License.txt`) |
| `quaternius/characters/Superhero_Female_FullBody.*`, `Superhero_Male_FullBody.*` and their textures | Universal Base Characters, Standard tier | https://quaternius.com/packs/universalbasecharacters.html | CC0 1.0 (`License_Standard.txt`) |
| `quaternius/hair/Hair_Long.*`, `Hair_Buzzed.*`, `Hair_Beard.*` and `T_Hair_*` | Universal Base Characters, Standard tier (hairstyles rigged to the head bone) | as above | CC0 1.0 |
| `quaternius/outfits/Female_Ranger_*`, `Male_Ranger_*`, `T_Ranger_*`, `T_Regular_*` | Modular Character Outfits – Fantasy, Standard tier | https://quaternius.com | CC0 1.0 (`License_Standard.txt`) |
| `weapons/Sword_Big.fbx`, `weapons/Dagger.fbx` | LowPoly Medieval Weapons (pack dated 2018-09-10) | https://quaternius.itch.io/lowpoly-medieval-weapons | CC0 1.0 (stated on the itch.io page; the zip has no licence file) |

## What was changed

`game/tools/import_assets.gd` copies these files from the downloaded packs and changes them as follows (all allowed under CC0):

- textures scaled down with Lanczos filtering: base colour to at most 2048 px, normal, ORM and roughness maps to at most 1024 px;
- the bodies' broken texture references (`T_Eye_Normal_png.png`, `T_Hair_1_Normal_png.png`) pointed at the files that exist;
- the outfits use the pack's unreferenced, darker `T_Ranger_3_BaseColor` colourway instead of the green `T_Ranger_BaseColor`;
- the weapons' flat colours replaced at import by the game's own materials (`game/weapons/materials`).

Derived files outside this folder: the head-only meshes (`game/fighters/heads`, cut from the base bodies by `game/tools/cut_heads.gd`), the palette textures (`game/fighters/*/…_outfit.png`, recoloured from `T_Ranger_3_BaseColor` by `game/tools/bake_palettes.gd`) and the shared clip library (`quaternius/animations/ual_library.res`, built from the two GLBs by `game/tools/build_animation_library.gd`).

The Katana (`game/weapons/katana`) is original to this project, built in code by `game/tools/build_katana.gd`.
