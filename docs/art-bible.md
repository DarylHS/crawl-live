# Crawl Live! art bible (draft)

Status: draft for the deferred "Later: visual polish" phase in `PHASES.md`. Section 9 records what P9 built. All art work stays in `ui/art/` and `godot/assets/`, so the rules never change.

## 1. Visual identity

Crawl Live! is a dungeon that is also a television show. The crawler is a contestant, the monsters are cast members, the bosses are billed like a running order (Opening Act, Featured Act, Headliner), and a sarcastic System AI narrates everything to a live audience. The look should say "cheap studio set built inside a real dungeon": honest stone and grime underneath, with show business bolted on top (gaffer tape, sponsor logos, stage lights, price tags, lanyards).

Three rules carry the identity:

- **The dungeon is grim, the show is loud.** Walls, floors and ceilings are muted and desaturated. Anything the show put there (stairwell grates, the shop counter, boss accessories, loot boxes) gets the saturated accent colours.
- **Comedy lives in silhouettes and props, not gore.** A goblin in a supervisor's hi-vis vest, a skeleton with a clipboard, a vacuum bot with googly menace. Readable at 16 pixels high.
- **Original only.** No characters, logos, places or quotes from the books (the ground rule in `PHASES.md`). Sponsor logos are invented.

Floor moods follow the tints already in `firstperson.DEPTH_TINT`, and each floor's Headliner suggests a set dressing theme:

| Floor | Tint (r, g, b) | Mood | Set dressing (suggested by the Headliner) |
|---|---|---|---|
| 1 | 1.00, 1.00, 1.00 | Neutral grey stone, damp | Service tunnels and drains (The Grease Trap King) |
| 2 | 1.00, 0.95, 0.82 | Warm, dusty sepia | Archive stacks, card catalogues (The Overdue Librarian) |
| 3 | 0.86, 1.00, 0.88 | Sickly green, mine lamps | Half-built site, scaffolding, hazard tape (Foreman Gristle) |
| 4 | 1.00, 0.84, 0.84 | Candlelit rose | Cult chapel doubling as a green room (High Hexer Volka) |
| 5 | 0.84, 0.86, 1.05 | Cold blue fluorescent | Warehouse, pallets, cling film (The Shrink-Wrapped Colossus) |
| 6 | 1.05, 0.72, 0.66 | Infernal red | Studio floor and executive suite (Executive Producer Glorm) |

Safe rooms and stairwells are deliberately *not* tinted (the code already skips the tint for them), so they read the same on every floor: safe rooms are clean, pale green tiled "studio hospitality", stairwells are the gold grate.

## 2. The two views

Both views stay (first-person by default, Tab switches, Phase 7). They share one sprite per entity, so a goblin has the same silhouette, colours and props in both.

**Top-down (secondary view).** Currently 16 px glyph tiles, a 64 x 40 tile viewport scrolling over 120 x 76 floors, 256 px side panel and 128 px log. It needs terrain tiles (wall, floor, safe floor, safe wall edge, stairs open, stairs locked or sealed, doorway), furniture (bed, bench, counter), the player, every monster, Act and Headliner, every pet and every item. Fog of war (remembered but not visible) stays a code-side darkening, as now, so no "dim" variants are drawn.

**First-person (default view).** A 320 x 200 raycaster, scaled up with hard pixels. It needs wall, floor and ceiling textures per floor theme; safe-room wall and floor; stairwell floor grate (open and locked); and billboards for every monster, Act, Headliner, pet, item and piece of furniture, plus the floating stairwell arrow and padlock. There is no player sprite in this view (a weapon "view model" in the Wolfenstein style is an open question, see section 7).

**Keeping them consistent.**

| Concern | Rule |
|---|---|
| Silhouette | One source PNG per creature, item and piece of furniture, used by both views. No separate top-down and first-person drawings. |
| Palette | Both views draw from the shared palette in section 4. Monster base colours stay those in `entities.MONSTERS` so the log, minimap and HUD colours still match. |
| Boss tier | Same tier outline colour in both views (top-down already draws a 1 px tier-coloured box; with tiles it becomes the sprite outline). |
| Terrain | Top-down floor and wall tiles are 32 x 32 crops or reductions of the same 64 x 64 first-person textures, so floor 3 looks like floor 3 from either angle. |
| Lighting | Top-down keeps lit/dim by tile; first-person keeps distance fog. Neither bakes lighting into the art. |

## 3. Sizes for the raycaster

**What the screen actually shows.** On-screen heights in the 320 x 200 internal frame (before the upscale), from the code: wall height = 200 / d; billboard size = 200 / d x scale, where monsters use scale 0.62 to 0.71 (by HP), Opening 0.85, Featured 0.95, Headliner 1.0, pets 0.5, furniture 0.75, items 0.32.

| Distance (tiles) | Wall | Monster (0.7) | Headliner (1.0) | Pet (0.5) | Item (0.32) |
|---|---|---|---|---|---|
| 1 | 200 | 140 | 200 | 100 | 64 |
| 2 | 100 | 70 | 100 | 50 | 32 |
| 3 | 67 | 47 | 67 | 33 | 21 |
| 4 | 50 | 35 | 50 | 25 | 16 |
| 6 | 33 | 23 | 33 | 17 | 11 |
| 8 (light radius) | 25 | 17 | 25 | 13 | 8 |

**Textures: 64 x 64, power of two.** A wall texel is 200 / (64 x d) screen pixels, so about 3 pixels at distance 1, 1:1 at about distance 3, and minified 2.5:1 at the light radius. 64 is the sweet spot:

- 32 x 32 would be 6 pixels per texel up close, too coarse against 32 px creature sprites that sit at about 4 pixels per texel.
- 128 x 128 only adds detail inside about 1.5 tiles, and with no mipmapping it doubles the shimmer and moiré on far walls and on the floor (floor rows near the horizon are already heavily minified). Memory is not the issue (64 x 64 x 3 bytes is 12 KB per texture); aliasing is.
- Power of two keeps the `% TEX` wrap and the stacked `(n, 64, 64, 3)` numpy texture array simple, and lets a future change use bit masks.

**Billboards: 32 x 32 for everything, 64 x 64 optional for Headliners.** The goal is roughly matching pixel density between sprites and walls so the scene doesn't look like mixed resolutions. Density matches when sprite size is about 64 x scale: about 42 for ordinary monsters, 64 for Headliners. 32 x 32 is the nearest power of two for monsters, pets, furniture and items (items are drawn small, so 32 x 32 gives them more than enough), matches the existing body-plan sprites and DCSS tiles exactly, and is still only about 2 pixels per texel at distance 2 where most fights happen. Headliners at scale 1.0 can justify a 64 x 64 sprite; if a pack only provides 32 x 32, upscale it 2x nearest-neighbour and add hand detail.

**Rules for every billboard.**

- Anchor: feet on the bottom row, centred horizontally. The code places sprites with their bottom edge on the floor line, so empty rows at the bottom make creatures float. Floating things (ghosts, the stairwell arrow) leave their gap on purpose.
- Transparency: 32-bit PNG with binary alpha (0 or 255 only). No anti-aliased edges, no soft or baked drop shadows (the code draws item shadows and computes outlines from `alpha > 0`, so partial alpha creates grey halos). If a source sheet has no alpha, use colour key magenta (255, 0, 255) and convert on load.
- Outline: leave a 1 px transparent border on every side so the code-drawn outline (dark for normal monsters, tier colour for bosses) is not clipped.
- Facing: front-facing billboards only, one angle. The rules have no monster facing, the camera only ever looks along four directions on a grid so most encounters are head-on, both candidate packs ship one view per creature, and 8-angle sprites would multiply the art for 18 creatures by eight for little gain in a turn-based game.
- Animation: one frame is the baseline. Optional later: a 2-frame idle (breathing or bob) at about 2 fps, and a second frame for Glorm's phase two. Hit flashes, death fades, screen shake and floating damage numbers are code effects (as already planned), not drawn frames.
- Lighting: sprites are drawn flat lit from above, mid values. The code already darkens the lower half and applies fog, so do not bake dark lower halves into the art.

**Per-floor tint compatibility.** The tint multiplies RGB (up to 1.05), so floor, wall and ceiling textures must be authored near-neutral and mid-value: mostly greys and grey-browns, no pure white (it clips under 1.05) and no strongly saturated hues (they fight the tint, e.g. a blue brick under the floor 6 red tint turns to mud). Detail should come from value, not hue. Sprites, safe-room and stairwell textures are not tinted; keep it that way so creatures read the same on every floor.

## 4. Palette and readability

Use one master palette of about 32 colours built from the existing `config.py` constants as anchors, with 3 to 5 step ramps for stone greys, skin and fur browns, metals, and the show accents (gold `ACCENT` (255, 196, 64), red `DANGER` (235, 80, 80), blue `INFO` (110, 170, 240), green `GOOD` (110, 210, 120)). Imported art gets snapped to it in a batch step so DCSS tiles by different artists sit together.

| Rule | Why |
|---|---|
| Accent colours are reserved: tier outlines blue (110, 170, 240) Opening, gold (255, 196, 64) Featured, red (235, 80, 80) Headliner. Normal monster outlines stay near-black (14, 12, 18). | Players learn "coloured outline = boss" quickly. |
| Never rely on hue alone. Tiers also differ by scale (0.85 / 0.95 / 1.0, already in code) and by a prop: Opening Acts wear a lanyard badge, Featured Acts a star sash, Headliners their own unique look. Top-down adds a 2 px outline for Headliners. | Red and gold can be hard to tell apart for some colour-blind players; blue and gold are the safest pair. |
| Locked stairs are red with a padlock in both views (top-down currently only changes colour; add the padlock). | Same reason; red-green confusion with the green safe room. |
| Safe rooms are identified by pattern (pale square tiles, clean grout) as well as green. | Floor 3's green tint could otherwise read as "safe". |
| Every creature needs a value contrast of at least about 40% luminance against the floor at fog level 0.5. Check the Shadow Stalker (110, 110, 230) on floor 5's blue tint and Glorm (255, 90, 90) on floor 6's red tint; both need a lighter rim or brighter eyes. | Blue-on-blue and red-on-red vanish at distance. |
| Eyes are the brightest pixels on any creature. | The one feature that survives fog at distance 8. |
| Item kinds keep a consistent shape language: weapons diagonal, armour as a torso shape, potions as bottles with the existing pink-red ramp, bombs round with a fuse, junk greyish. | Matches the glyph families `) [ ! * ~` so players moving from `--glyphs` can still read them. |

## 5. Kenney or Dungeon Crawl Stone Soup

Licence checks: I could not reach opengameart.org or kenney.nl directly from this session (DNS failure), so the licence points below come from web search summaries of those pages and of Debian's copyright file for Crawl. Treat them as likely but recheck before importing anything.

| | Kenney (e.g. Tiny Dungeon, Roguelike/RPG pack) | DCSS tiles (OpenGameArt "Dungeon Crawl 32x32 tiles" and supplemental set) |
|---|---|---|
| Licence | CC0 per Kenney's support page and his OpenGameArt listings (from search, not fetched). | Listed as CC0 on OpenGameArt (from search, not fetched). Debian's copyright file lists Crawl's `source/rltiles/*` as CC0-1.0 but says the history of older tiles is complex; the original RLTiles site calls its tiles public domain yet asks for attribution text. Not verified per tile. |
| Attribution | Optional; credit "Kenney" if you do. Kenney's logo may not be used. | "No attribution required" per the OGA listing, with a courtesy link requested. Credit anyway, because of the RLTiles ancestry above. |
| Art style | Clean, chunky, cohesive, cute. Very consistent within a pack. Light comic tone suits the show. | Detailed fantasy pixel art by many artists. Rich but uneven, and played straight rather than comic. |
| Sizes | 16 x 16 for the roguelike packs (Tiny Dungeon's size is inferred from its collection name, not confirmed). | 32 x 32 throughout; over 3,000 tiles in the main set plus a similar supplemental set. |
| Top-down coverage | Good for terrain, generic monsters (skeletons, goblin-likes, ghosts), chests and some props. Few items. | Excellent: walls and floors in many materials, stairs, doors, hundreds of monsters, thousands of items. |
| First-person coverage | Weak. 16 px art is 8 to 9 pixels per texel at distance 1 against 3 for walls, so it clashes with 64 x 64 textures; no wall textures at a usable size. | Fair. 32 px sprites match the billboard size exactly. 32 x 32 wall tiles can be tiled 2 x 2 or redrawn at 64 x 64 for wall faces; they are top-down tiles, so wall faces still need work. |
| Fit to this game's entities | Rat, skeleton, goblin, ghost-like, maybe a brute. Little for vacuum bots, cultists, golems, pets beyond basics, or the comic items. | Rat, goblin, skeleton, ogre or troll (brute), robed humans (cultist), golems, shadows and wraiths (stalker), many potions, weapons and armour, a hammer and a katana-like blade. No vacuum bot, budgie, bed, shop counter, sock, mug, remote, trophy, party popper or fire extinguisher. |
| Consistency risk | Low inside one pack; high if mixed with anything else. | Medium; needs a palette snap and outline pass. |
| Fill-in art still needed | Most of first-person (all textures, most billboards upscaled or redrawn), most items, all bosses. | About 25 sprites (see section 6): all six Headliners' props, Act badges and sashes, vacuum bot, budgie, furniture, comic junk items, fireworks, popper, extinguisher, plus 64 x 64 wall, floor and ceiling textures for six floors. |

**Recommendation: DCSS 32 x 32 tiles as the base, with original fill-in art in the same style.** Reasons: 32 x 32 is the size the raycaster wants for billboards, so one file serves both views and the "same silhouettes" rule comes free; coverage of monsters, items and terrain is far wider, which means fewer hand-drawn pieces; and its stone and brick tiles give a starting point for the 64 x 64 wall textures. Kenney's tone fits the show better, but its 16 px art would leave first-person looking mismatched and still need most of the work redrawn. Do not mix the two packs. The comedy comes from our own props and Headliners layered onto DCSS bodies. Keep a credits file listing every source tile and its artist where known, even if CC0 makes it optional.

Consequence for the top-down view: DCSS at 32 px does not fit the current 16 px grid. Recommended: top-down draws 32 px tiles with a 32 x 20 tile viewport in the same 1024 x 640 map area (the FOV radius of 8 needs only 17 tiles, so it fits), plus a zoom-out key that falls back to the 16 px glyph overview. See open questions.

## 6. Asset list and layout

Keys come from the code: `entities.MONSTERS`, `entities.PETS`, `bosses.BOSSES` (as `boss_<depth>`), Acts as `<tier>_<base>`, `items.ITEMS`, `dungeon` tile constants and `Floor.furniture` kinds, `loot.BOX_TIERS`.

**Terrain and textures**

| Key | Top-down (32 x 32) | First-person (64 x 64) | Notes |
|---|---|---|---|
| `WALL` | Wall top per floor theme | `wall` per floor, 2 to 3 variants picked by tile hash | Tinted; author neutral. |
| `FLOOR` | Floor per floor theme | `floor` per floor | Tinted. |
| ceiling | none | `ceiling` per floor | Tinted; pipes and rigging on floor 6. |
| safe wall | Edge tile | `safe_wall` (pale tiles, a sponsor sign variant) | Not tinted. |
| safe floor (and doorway) | Pale tile | `safe_floor` | Not tinted. |
| `STAIRS` open | Gold grate | `stairs_open` (gold grate) | Plus floating arrow billboard. |
| `STAIRS` locked or sealed | Red grate with padlock | `stairs_locked` (dimmed red grate) | Plus red arrow and padlock billboard. |

**Furniture** (`FURNITURE` tiles, kinds from `dungeon._add_safe_room`): `bed`, `bench`, `counter`. One 32 x 32 sprite each, used as the top-down tile and the billboard (scale 0.75). All fill-in art: a camp bed with a sponsor blanket, a workbench with vice, a shop counter with till and price board.

**Creatures** (one 32 x 32 sprite each unless noted; same file in both views)

| Key | Name | DCSS starting point | Fill-in needed |
|---|---|---|---|
| `gnawer` | Sewer Gnawer | Rat | Palette only |
| `goblin` | Knockoff Goblin | Goblin | Cheap knock-off logo tee |
| `vacbot` | Feral Vacuum Bot | None | Full sprite |
| `skeleton` | Grumpy Skeleton | Skeleton | Scowl, maybe a clipboard |
| `brute` | Tunnel Brute | Ogre or troll | Hard hat |
| `cultist` | Hex Cultist | Robed human caster | Hood colour |
| `golem` | Flesh Golem | Flesh golem or abomination | Stitches |
| `stalker` | Shadow Stalker | Shadow or wraith | Lighter rim for floor 5 |
| `opening_<base>` (8) | Opening Acts | Base sprite | Lanyard badge overlay; blue outline in code |
| `featured_<base>` (8) | Featured Acts | Base sprite | Star sash overlay; gold outline in code |
| `boss_1` | The Grease Trap King | Slime or jelly | Crown, grease drips |
| `boss_2` | The Overdue Librarian | Robed human | Glasses, book stack |
| `boss_3` | Foreman Gristle | Large humanoid | Hard hat, hi-vis |
| `boss_4` | High Hexer Volka | Robed caster | Horns, staff |
| `boss_5` | The Shrink-Wrapped Colossus | Large blob or golem | Cling film sheen |
| `boss_6` | Executive Producer Glorm | Demon | Tie, headset; phase two variant |
| `cat` | Alley Cat | Cat or feline, if present | Check coverage |
| `dog` | Scruffy Dog | Hound or jackal | Floppy ears |
| `budgie` | Chatty Budgie | None found | Full sprite |
| `mouse` | Scheming Mouse | Small rat | Shifty eyes |
| player | Crawler | Human base | Top-down only; one per race (6) or one generic, see open questions |

Headliners may be 64 x 64 (section 3); Acts reuse their base sprite with an overlay, so 16 Act looks cost 2 overlays.

**Items** (32 x 32; billboard scale raised from 0.32 to about 0.4 when real art replaces glyphs)

| Kind | Keys | DCSS starting point | Fill-in needed |
|---|---|---|---|
| weapon | `pan`, `cleaver`, `katana`, `extinguisher`, `sledge` | Cleaver-like blade, katana, war hammer | Frying pan, fire extinguisher |
| armour | `jersey`, `vest`, `plate` | Leather, scale or plate armour | Gym jersey, riot vest recolours |
| potion | `tonic`, `brew`, `elixir` | Potion bottles | Recolour to existing pink-red ramp, sponsor label |
| bomb | `popper`, `fireworks` | None suitable | Both |
| junk | `sock`, `trophy`, `remote`, `mug` | None | All four |

**Show and UI extras**: loot box icons for `bronze`, `silver`, `gold`, `platinum`, `legendary` (menus and the reveal screen, 32 x 32 and a 64 x 64 reveal version), stairwell arrow and padlock (replacing `stairs_sprite`), stairwell key and map scroll icons for drop toasts. Optional: weapon view models for first-person (fists plus 5 weapons).

**File layout**

```
assets/
  manifest.json          # key -> file, size, anchor, scale override, source, author, licence
  CREDITS.md             # generated from manifest.json
  textures/floor1..6/    # wall_0.png, wall_1.png, floor.png, ceiling.png (64 x 64)
  textures/common/       # safe_wall.png, safe_floor.png, stairs_open.png, stairs_locked.png
  tiles/floor1..6/       # top-down wall.png, floor.png (32 x 32, cut from the textures)
  sprites/monsters/      # gnawer.png ... stalker.png
  sprites/acts/          # badge_opening.png, sash_featured.png (overlays)
  sprites/headliners/    # boss_1.png ... boss_6.png, boss_6_phase2.png
  sprites/pets/  sprites/items/  sprites/furniture/  sprites/player/  sprites/fx/
  ui/boxes/
```

Original pack downloads are kept outside the repo; only the edited PNGs are committed.

**Data-driven mapping.** A small loader in `crawler/ui/art.py` reads `manifest.json` once and returns a surface for a key such as `mon:goblin`, `boss:boss_3`, `pet:cat`, `item:pan`, `furn:bed`, `tex:1:wall` or `box:gold`, or `None` if the key or file is missing. `hud.py` and `firstperson.py` call it first and fall back to today's code (glyph, body plan, procedural texture) on `None`, so new content works before it has art and nothing ever crashes on a missing PNG. A `--glyphs` flag in `main.py` (and a settings toggle) skips the loader entirely for the current look; the same path is used automatically if `assets/` is absent. Tests: a headless check that every key in `MONSTERS`, `BOSSES`, `PETS`, `ITEMS`, the furniture kinds and `BOX_TIERS` has a manifest entry or sits in an explicit "fallback allowed" list, that every PNG has the right size and binary alpha, and the existing render tests run once with art and once with `--glyphs`.

## 7. Open questions for the owner

1. Top-down tile size: accept 32 px tiles with a 32 x 20 tile viewport and a zoom-out to the 16 px glyph overview, or keep 16 px and accept downscaled art?
2. Player look in top-down: one generic crawler, one per race (6, chosen on floor 3), or paper-doll gear layers?
3. First-person weapon view model (hands holding the equipped weapon, Wolfenstein style): wanted, or keep the clean view?
4. Tone: how far should comedy go in the art? Props only (recommended), or a fully cartoon restyle?
5. Is the 2-frame idle animation worth the extra art, or single frames for now?
6. Credits: happy to credit DCSS artists and the source pages in-game and in `CREDITS.md` even where CC0 makes it optional?
7. Budget for fill-in art: about 25 sprites and 18 to 24 textures. Hand-drawn by you or a commissioned artist, or generated procedurally as now and refined?
8. Should Acts get their own sprites later, or are badge and sash overlays on the base monster enough?

### Owner decisions (after Godot port P4)

The owner accepted every recommendation:

| # | Decision |
|---|---|
| 1 | Top-down uses 32 px tiles (32 x 20 tile viewport) with a zoom-out key to the 16 px glyph overview. |
| 2 | Top-down player sprite: one per race (6). |
| 3 | First-person weapon view model: yes, added in P8 (procedural placeholders, one per starting weapon; see section 8). |
| 4 | Comedy in props only, no cartoon restyle. |
| 5 | Single frames for now; idle frames later for bosses only. |
| 6 | Credit DCSS artists and source pages in-game and in `assets/CREDITS.md`. |
| 7 | Fill-in art generated procedurally first; commission the ones that matter most (Headliners, vacuum bot) later. |
| 8 | Acts use badge and sash overlays on the base monster; unique sprites for bosses only. |

## 8. Weapon view model and effects (P8)

Effects are code, not drawn frames: flashes, floating numbers, shake, particles, torch flicker and slides need no art. Two art hooks were added for P9:

| Key | Picture | Notes |
|---|---|---|
| `wpn:<item>` (`wpn:pan`, `wpn:cleaver`, `wpn:katana`, `wpn:extinguisher`, `wpn:sledge`) | 80 x 80, binary alpha, the hands and sleeves included | Grip at about x 44, y 62 near the bottom; the sleeves run off the bottom edge. Shown at 1 picture pixel per pixel of the 320 x 200 frame (nearest filter), so it sits in the same pixel grid as the world. |
| `wpn:blade`, `wpn:blunt`, `wpn:unarmed` | the same, used for any weapon of that style with no picture of its own | `unarmed` is two fists. |
| `fx:torch_0`, `fx:torch_1` | 32 x 32, the wall torch (bracket and flame) in two flicker frames | Drawn with the billboard shader, fog only. |

The placeholders are drawn by `ui/art/weapon_art.gd` and `SpriteArt.torch`; register real PNGs under those keys (`SpriteArt.register` or the manifest) and nothing else changes. Palette: hands and sleeves use skin tones and a dark blue contestant sleeve with the near-black (20, 16, 24) outline; floating numbers use the accent colours (white hits, gold crits, red damage taken, green healing, blue pet).

## 9. As built (P9)

**Source and licence, rechecked at the source.** The tiles come from `github.com/crawl/tiles` (a repository of the Crawl Stone Soup tiles, snapshot `releases/Nov-2015`, commit `a6ea1655`). Its README says the artists listed in its `ARTISTS.md` signed their tiles over to CC0 1.0 and that tiles of unclear ownership are left out of the export and listed in `TILES_UNDER_UNKNOWN_LICENSE.md`; there is no separate LICENSE file, so CC0 rests on that statement and on the artists list. `scripts/art_build.py` refuses to use anything on the excluded list (it checks every tile it opens). Credit is given in `godot/assets/CREDITS.md` (per file: key, picture, origin, source tile path, licence) and on the title screen; the Kenney packs were not used (not rechecked: DCSS only, as recommended).

**Cleaning.** Binary alpha, DCSS's black outline and ground shadow removed from creatures (the game draws its own outline and shadows), a one pixel transparent border, feet on the bottom row inside it (a sprite wider or taller than 30 px loses whole lines of its quietest rows rather than being resampled), snapped (CIE Lab nearest) to a 56 colour master palette built from the `config.py` anchors (`art_pipeline.PALETTE`; a little over the bible's "about 32" because fewer colours turned skin and stone to mush). Textures are desaturated to a quarter of their chroma, levelled to a mean luminance of 108 (walls) and 78 (floors), capped at 215 so the floor 5 and 6 tints do not clip, and snapped to the grey and grey-brown ramps only. Top-down tiles are the 64 px textures reduced by every second pixel, so both views match.

**Coverage.**

| Origin | Keys |
|---|---|
| DCSS direct (53: 19 sprites, 34 wall, floor and tile pictures) | gnawer (quokka), cultist (necromancer, hue matched), golem (flesh golem), cat, dog (jackal), mouse (lab rat, recoloured), the six race sprites and the pre-race crawler (paper dolls of base, clothes and hair; hobgoblin, bog troll (recoloured deep troll) and houseplant (thorn hunter) from monster tiles), cleaver (hand axe), katana (scimitar, recoloured), sledge (large mace), jersey (robe), vest (leather armour), plate; the two walls and the floor of each of six floors, as 64 px textures and 32 px tiles (floor themes below) |
| DCSS plus fill-in (19: 13 sprites, 6 pictures) | goblin (green, logo tee), skeleton (clipboard), brute (ogre with a hard hat), stalker (shadow wraith with a lighter rim), the six Headliners (royal jelly with a crown; a librarian with glasses and books; an iron giant with a hard hat and hi-vis; a sorceress with horns and a staff; a guardian golem in cling film; a balrug with a tie and headset), tonic, brew and elixir (DCSS bottles recoloured, with sponsor labels), safe wall and floor (marble recoloured pale green on a clean 16 px grid), the floor 3 hazard-tape wall |
| Fill-in drawn in code (39: 29 sprites, 10 pictures) | vacuum bot, budgie, Act badge and sash overlays, pan, extinguisher, popper, fireworks, sock, trophy, remote, mug, bed, bench, counter, the stairwell arrows (open, locked with padlock), torch frames, five loot boxes (32 and 64 px), six ceilings (pipes, beams, boards, vaulted ribs, corrugated roof, lighting grid), the gold and red stairwell gratings |
| Still placeholders | the first-person weapon view models (`wpn:*`, DCSS has no first-person art), the reveal animation's gift box (`RevealCanvas`, drawn in code and animated), sounds |
| Not done | 64 px Headliners (all 32 px, scaled by the code as before), a phase-two Glorm picture (no phase-two key exists), the sponsor-sign wall variant, the doorway tile, 2 to 3 wall variants per floor (two per floor, picked by hash), idle frames |

**Floor themes (the stone keys).** 1 grey brick and flags (service tunnels, ceiling pipes); 2 brown brick and carved panels (archive stacks, ceiling beams); 3 bare stone, rough dirt and a hazard-tape wall (building site); 4 pale church stone, crypt wall and tomb flags (chapel, vaulted ribs); 5 metal and white metal panels over a mesh floor (warehouse, corrugated roof); 6 relief and silver walls over polished marble (studio, lighting grid). The tint rules are unchanged (safe rooms and stairs untinted), and the top-down view applies the same tints.

**Open choices.** The race sprites show a doll, not the character's gear (art bible 7.2: one per race). Acts reuse the base body, so an Act on the cultist wears the cultist's hue. DCSS art is played straight; the comedy is in the props drawn over it (hard hats, clipboards, logos, labels, sponsor blankets).
