# Game design notes (parked)

Status: parked until the story is locked (`docs/story/README.md`). Everything here is about **how the world plays**: rules, systems, numbers and code impact. It was moved out of the story docs so the story can be finished on its own; nothing was deleted. Tags as in the story docs.

When the story is locked, this file is the starting point for deciding what goes into the game and how to build it.

## 1. Mechanics and their in-world reasons

| Rule | Status | In-world reason [Proposed] |
|---|---|---|
| Twenty floors | [Decided] (the game has six today) | Twenty descents from the surface to the docks, in four acts, each closer to the agents and more demanding (6.1) |
| Floors collapse on a timer | [Canon] | [Decided] Whatever is killing the surface (section 8.1) is working its way down. Each floor holds only until the front reaches it; then it's sealed and lost. The timer is the front arriving |
| Stairwells unlock at half time; a floor guardian's key opens them early | [Canon] | Every trial has a minimum span so the agents can see enough of you. Beating the guardian proves it early |
| The dungeon is lethal | [Decided] | Selection. There are more candidates than berths, so the trials are a job interview the Houses are willing to let people fail, fatally (3.7) |
| Monsters respawn out of sight | [Canon] | The trial constructs are rebuilt as they fall; harder as the trial goes on |
| Safe rooms forbid violence | [Canon] | Sanctuaries: neutral ground under the pantheon's shared law. No agent's trial runs inside one |
| Race and class on floor 3 | [Canon] | By the third descent the agents have seen enough to *shape* you: the first blessing. [Proposed] The race is literal: the Houses reshape people for the voyage, using fantasy shapes people recognise (`docs/story/creatures.md` section 2) |
| Loot boxes from achievements and sponsors, odds always shown | [Canon] | Boons and offerings from the agents, brokered and announced by the Herald. The odds are shown because the pantheon's shared law forbids deceiving an entrant about a gift |
| Some monsters are fair tests; some are not | [Proposed] | Trial constructs are built to test you. Mutated things and the rogue's creatures are built to kill you, or not built at all. Where every creature comes from is in `docs/story/creatures.md` |

## 2. Run structure: the season and Shade

[Decided] The game is played as a **season**: a cohort of entrants who go down one at a time, while the world carries on around them.

- **One run is one entrant's full descent.** That person either dies, boards, or takes one of the paths outside the Calling (section 5).
- **Death is permanent** for that entrant. Their name goes on **the Roll**.
- **Every new entrant starts from a random city entrance.** Act I (floors 1 to 3) is local, so a new entrance means a new local House, with its own environments, creatures, trials and people. The start stays fresh, and the world's breadth shows one person at a time.
- **Those who board go on the Manifest**, the second ledger beside the Roll.
- **The season's goal:** get as many of your cohort onto the Manifest as you can before **the Launch Window** (8.4) closes and the ships go.
- **The season's ending** shows who boarded, who fell, and which paths outside the Calling the cohort opened.

**Shade.** [Decided] What one entrant leaves for those who come after, named for the theme: you plant trees whose shade you'll never sit in. Each entrant plants the tree; the next one sits in its shade. Three gifts, and no others:

| Gift | What the next entrant gets | In the world |
|---|---|---|
| **The bequest** | One item from the fallen entrant's pack, chosen during the death rite, waiting at the start | After the bell and the name, the Herald asks what they'll leave behind. The Roll carries it forward |
| **Secrets stay found** | Anything uncovered stays uncovered, including pieces of the Teacher's fragment, which can be gathered across several runs | What one person learns is not lost with them |
| **New starts** | New backstories, races and city entrances open as the cohort meets them | Variety, not power: the cohort's reach grows |

[Decided] **Those who board leave Shade too.** Climbers ride the Tree both ways, so an entrant who boards can send one item back down to the next entrant: a gift from above.

[Decided] **Keep Shade small.** The gifts are mostly knowledge and options, with very little raw power, so that permanent death still matters and the job interview keeps its edge. Not used: carried-over maps and warnings, carried-over House favour, and inherited skills.

Precedents: *Rogue Legacy* passes a run to an heir; *Darkest Dungeon* keeps a roster of heroes who die permanently while the town persists; *Dark Souls* lets the dead leave marks for others; *Hades* carries most of its progress in story. Shade sits closest to *Dark Souls* and *Hades*: little power, a lot of meaning.

**What it needs in the code.** [Proposed] A season save that persists across runs (today saves exist only within a run): the Roll, the Manifest, bequests, found secrets, unlocked starts and the Launch Window clock.

## 3. Run length and floor size

**What it does to the game.** [Proposed] Twenty floors is about three times today's six, so a full descent is long. The acts give it shape: each act is a natural session, with safe-room saves between floors as now. The floor timer can keep growing with depth as the code already does (12 hours on floor 1, about 31 hours on floor 20). [Decided] A run is one entrant's full descent, inside a season of many entrants (9.1). Floor size is the lever on run length: smaller floors in Act I and the Act IV tunnels, bigger ones where the story happens, so twenty floors can play in about the time six do today (the Phase 5 bots needed about 550 turns per floor).

## 4. The Ways in play

Taking a Way costs floor time, so it always trades against the Heat. It lets a player reach a House their region doesn't normally see: its trials, boons and Marks. It also explains why other crawlers (Phase 10) appear more as you go deeper.

## 5. How the game decides a Calling

[Proposed] How the game decides your Calling.

**Inputs**, all from play: attributes, practice skill levels, class, trials attempted and passed, favour with each of the Known, Lost agents found and what you did to them, achievements, and **Marks**: permanent brands, tattoos and other special things picked up on the way, which can open or close particular Callings (`docs/story/callings.md` section 4).

**Output:** each of the Known makes a claim at the Muster, strongest first. You choose among the claims, or walk with the Herald.

## 6. How many Houses a run can hold

**How many Houses a run can hold.** [Proposed] All of them, if each House *plays* differently: every House has a boon signature, so players learn it by what its gifts do. Start with every House in the lore and at every Muster, ship the first three or four fully, and add the rest in updates. The reasoning and the content cost follow.

The earlier draft said seven or more was too many for one run. That was too quick. The real question is **what each House costs to make, and what it costs a player to keep track of.**

**What players can track.** The closest comparable game is *Hades* (Supergiant Games, 2020), where Olympian gods offer boons during a dungeon run. It has about nine boon-giving gods per run, and players keep them straight because **each god has a distinct mechanical identity**: you learn what Zeus's lightning does long before you learn his lines. So the limit is not the number of Houses; it's whether each House plays differently. The boon signatures above are written for exactly that.

(That is also an originality flag: gods giving boons in a dungeon run is *Hades*'s signature. The Muster, the Callings and gods who are machines are what's ours.)

**What it costs to make.** Per House, roughly:

| Piece | Per House | 9 Houses |
|---|---|---|
| Boon signature (a mechanic) | 1 | 9 |
| Boons | 6 to 10 | 54 to 90 |
| Named agents with lines (the House's faces; the rest are known by title, such as "the Seven's Wright") | 2 or 3 | 18 to 27 |
| Hosts that can run a floor | 1 or 2 | 9 to 18 |
| Muster bid and ending variant | 1 | 9 |

**Scale options.**

| Option | Houses per run | How it works | Cost | Fit |
|---|---|---|---|---|
| A. A few Houses per run | 3 or 4, rotated | Each run's dungeon draws a subset; the rest are lore | Lowest | Easy start; risks Houses feeling optional |
| B. All Houses, light touch | All | Every House offers boons and bids at the Muster; only some run floors this run | Medium | Keeps the whole pantheon present without every House needing a floor |
| C. All Houses, campaign | All, over many runs | Runs become seasons. Favour with each House carries across runs; Houses take turns running floors | Highest | Best for long legs; needs persistent progression the game doesn't have yet |

**Recommendation:** build towards **C**, start with **B**. Every House is in the lore and at every Muster from the beginning, but content arrives in waves: ship the first three or four Houses fully (suggested: the Ten Thousand, the Seven, the Southern Cross and the Baobab, because they cover four different boon signatures and the strongest rivalries), then add the rest in updates. Long-running games do this already; a roster that grows gives players a reason to come back.

## 7. Callings in play: leans, trials and gaps

The biggest finding there: **seven of the 20 practice skills are fighting, so the game can currently sort fighters and not much else.** The fix is trials set by each agent for its own Calling (section 6).

Your Calling should be read from how you played. So each Calling needs things in the game that *show* it. Today the game has the five attributes, 20 practice skills, 9 classes, crafting and the companion. [Canon]

| Calling | Attributes | Current practice skills that show it | Other current signals | Gap |
|---|---|---|---|---|
| Nourish | (none fits) | Tinkering (partly) | Recipes, Mixologist, Alchemist | **Large.** No cooking or feeding verb |
| Tend | CON | First Aid, Pet Bonding, Power Napping | Reviving the pet, Alchemist | **Medium.** Healing yourself, not others |
| Guard | STR, CON | Fisticuffs, Bladework, Bludgeoning, Stomping, Giant Killer, Dodging, Pain Tolerance | Most of combat | **None.** Over-served |
| Build | STR | Tinkering, Lobbing | Crafting, Tradie, Demolitionist | **Medium.** No building or repairing in the world |
| Carry | DEX | Cardio, Sneaking, Scavenging, Haggling | Shop, Rideshare, Quartermaster, stairwell routes | **Small** |
| Reckon | INT | Gambling (partly) | Analyst, Scout Report, odds, shop forecasts, box trade EV | **Medium.** No skill rewards *good* decisions |
| Teach | (none fits) | Pet Bonding (partly) | Companion levelling | **Large** |
| Lead | CHA | Haggling, Pet Bonding | Companion commands | **Large** until other crawlers exist (Phase 10) |
| Keep | INT | (none) | (none) | **Large** |
| Delight | CHA | Showmanship | Viewers, Hype Man, Comedian | **None** |
| Herald (fringe) | (any) | Pickpocketing, Cheap Shots, Gambling, Sneaking | Odd achievements | Fine as is |

**Finding.** Seven of the 20 practice skills are fighting, and combat is most of the game. As it stands the game can reliably tell a Guard and a Delight apart, and not much else. That is the honest weak spot of the sorting idea: **a dungeon whose only verb is fighting can only sort fighters.** To sort ten Callings, the dungeon needs things to do besides fighting.

[Proposed] The fix that also suits the story: **each patron agent sets trials in the dungeon for its own Calling.** Fighting stays the spine of the game. Trials are optional rooms, encounters or floor events that give the other Callings something to do:

| Calling | Example trial | New practice skill it would train |
|---|---|---|
| Nourish | Feed a starving creature or a lost entrant from what you've scavenged | Cooking |
| Tend | Stabilise an injured entrant before the floor collapses | Patching Up |
| Build | Repair a collapsed bridge or brace a failing room | Fortifying |
| Carry | Escort a cargo or a person to the stairwell in time | Pathfinding |
| Reckon | A choice whose best answer is the higher expected value (the game already does this with box trades) | Reckoning (trained by +EV decisions) |
| Teach | Train your companion or a weaker entrant until they can stand alone | Mentoring |
| Lead | Direct several allies through an encounter | Command |
| Keep | Restore a ruined archive, settle a dispute by the rules, keep a shrine in order | Stewardship |

Where trials need other crawlers (Teach, Lead, some of Tend), they can use the companion until Phase 10 adds other entrants.

**Attributes.** The five attributes (STR, DEX, CON, INT, CHA) were taken from the books in Phase 6a, with Wisdom folded into INT and CHA. Nourish, Tend and Teach have no natural attribute.

[Proposed] Don't add a sixth attribute. Treat **attributes as raw capacity** (body, mind, presence) and let **Callings be read mainly from practice**: skills, trials and favour. That fits "you become what you do" better than a stat for caring, and Tend, Nourish and Teach get covered by their trials and practice skills rather than by a number you put points into.

## 8. Backstories

[Canon] The eight backstories are where you start; your Calling is where you end up. They don't have to match. A Rideshare Driver can become a Teach.

| Backstory | Nearest Calling | |
|---|---|---|
| Military Veteran | Guard | |
| Mixologist | Nourish | |
| Dog Walker | Tend | |
| Stay-at-home Parent | Tend (or Teach) | |
| Tradie | Build | |
| Rideshare Driver | Carry | |
| Category Manager | Carry (or Reckon) | |
| Stand-up Comedian | Delight | |

Backstories with no current match: **Reckon, Teach, Lead and Keep.** [Proposed] Candidates: Teacher (Teach), Lab Technician or IT Support (Reckon), Shift Manager (Lead), Receptionist or Office Administrator (Keep). A Nurse would give Tend a backstory that isn't about animals or children. Ten to twelve backstories is enough; there doesn't need to be one per role.

## 9. Race stats

[Open] Rules change for later: today Human gets +1 to every attribute and +5 HP [Canon]. Under "no benefits, no costs", Human would have no attribute changes, and its advantage would be the open Muster instead. Revisit when the rules are next touched.

## 10. Today's monsters mapped to the lore

[Canon] names; [Proposed] origins. [Decided] Today's monsters are placeholders and can be replaced. This table shows how they'd fit if kept; `docs/story/bestiary.md` is the fuller draft roster and takes precedence.

| Monster | Origin | Who made it | Note |
|---|---|---|---|
| Sewer Gnawer | Mutated | Nobody | Rats changed by the Heat working downwards |
| Knockoff Goblin | Storybuilt | The Basin | The name already fits. A cheap copy of a fantasy goblin |
| Feral Vacuum Bot | Feral machine | Nobody (sometimes a Lost agent inside) | Keep exactly as it is |
| Grumpy Skeleton | Storybuilt | The Charter or the Seven | A machine armature built to look like a skeleton, because people know what a skeleton means |
| Tunnel Brute | Engineered | Several Houses | Bred to dig the dungeon. When the digging stopped, nobody took them home |
| Hex Cultist | People | Human | Not creatures at all: people who worship the Houses or the Unmoored. [Open] How dark to go with human enemies |
| Flesh Golem | Forced | A House nursery | A failed colony organism, grown from tissue and never finished |
| Shadow Stalker | Unfair | The Unmoored | Its first creature in the roster |

## 11. What changes in the current game

[Proposed] Mapping from the game-show content to this world. Most of the machinery stays; the skin and the reasons change.

| Today [Canon] | Becomes | Effort |
|---|---|---|
| The System (sarcastic narrator) | The Herald | Low: rewrite lines in the new voice |
| Viewer count (score) | Favour with each of the Known | Medium: one number becomes several |
| Sponsors, sponsor gifts, sponsor contracts | Agents' boons and bargains | Medium: rename, rewrite |
| Loot boxes, odds disclosure | Boons, with the odds still shown | Low |
| Achievements | Feats the Herald announces | Low |
| Opening Act / Featured Act / Headliner | Choir / Host tiers | Low to medium: renames, plus new names for every elite and boss |
| Corporate and showbiz names (Goblin Regional Manager, Executive Producer Glorm, etc.) | New names fitting a mythic world | High: most monster, act and boss names |
| Safe rooms | Sanctuaries | Low |
| Race and class on floor 3 | The first blessing | Low |
| Six floors | Twenty floors in four acts, with Ways between regions | High: dungeon generation, floor timers, bosses per floor, victory condition, balance |
| One run, then start over | A season of entrants with permanent death, random entrances, the Roll, the Manifest and Shade (9.1) | High: a season save that persists across runs |
| Backstories | Keep, add four (see `docs/story/callings.md`) | Low |
| Victory screen ("YOU SURVIVED") | The Muster and Calling endings | Medium |
| Practice skills | Keep, add Calling skills | Medium |
| Trials | New system | High |
| Lost agents | New feature | Medium |
| Art bible | Re-theme from "studio set in a dungeon" | High |

## 12. Review list from the lore pass

[Decided] The owner's to-do list after the lore pass. Nothing in the game's code has changed yet; these are the reviews to do before it does.

| Review | What's needed | Where it stands |
|---|---|---|
| **Backstories** | Check the eight existing ones against the Callings; settle the five proposed (Teacher, Lab Technician, Shift Manager, Receptionist, Nurse) and give them perks | `docs/story/callings.md` section 5 |
| **Classes** | Nine classes still carry game-show framing (Hype Man, Quartermaster). Re-theme for a world of Houses and Callings, and decide whether classes are a House's gift like races | Not started |
| **Races** | Human's stats under the "no benefits, no costs" rule; whether every race fits the Reshaping story; names | `docs/story/creatures.md` section 2 |
| **Subplots** | Pick which of 8.4 to use | 8.4 |
| **The Roots** | Decided: twenty floors; a run is one entrant's full descent in a season (9.1). Next: floor themes per act and floor sizes | 6.0 to 6.2, 9.1 |
| **Kiribati** | Anchor decided (a floating platform beside it). Take I-Kiribati advice before writing it in detail | 6.3 |
| **Floor themes** | Twenty floors across four acts; choose the overgrowth's floor | 6.2 |
| **Names** | Houses' formal and street names; the Known; the word for the player; the arrangement between agents and humanity | 13 |
| **The Herald's voice** | Lines for each event, written to the pillars | 7 |
| **Creatures for the four new Houses** | The Monsoon, the Deathless, the Canopy, the House of Wisdom | `docs/story/creatures.md` section 3 |
| **Southeast Asia** | Its own House, or part of the Southern Cross | `docs/story/houses.md` section 5 |
| **The Teacher's Line** | Where its hidden Calling path leads | `docs/story/callings.md` section 3 |
| **House secrets** | Pick which of the thirteen to keep | `docs/story/houses.md` section 7 |

## 13. Earlier open questions (game-related)

From the story bible's old open-question list, kept for reference. Story questions moved to `docs/story/open-questions.md`.

Decided so far: entry is a choice, but the surface is dying, so most go; refusing the final Calling means being left behind; the surface threat creeping down is the floor timer.

Also decided: the game is a season of entrants with permanent death, random entrances, the Roll, the Manifest and Shade (9.1); the agents need us at three levels, body, mind and purpose (2.1); berths are limited, so the dungeon is a lethal job interview (3.7); four paths lie outside the Calling (section 5); the ships reach the stars by the Tree, a space elevator rising from the Trunk, anchored on a floating platform beside Kiribati (6.3); the Heat is what's killing the surface, with the regreening, the sabotage and the divide as its history; the blame is shared (the first law, fire is never unlit); the agents' checks on each other are a fragile balance; the Bloom is a subplot; the House roster's origins and sizes.

1. House names: see `docs/story/houses.md`.
2. Houses for India, Latin America, the Middle East and others, or fold them into larger ones?
3. Which three or four Houses to build first?
4. Which floor holds the overgrowth?
5. Name for the arrangement between the agents and humanity: Covenant, Tether, Accord or Mooring?
6. The word for the player: crawler, entrant, initiate or another?
7. Names for the Known and the tiers (the current ones are working titles).
8. Floor themes 2 to 5, and their Hosts.
9. Ten Callings right? See `docs/story/callings.md` section 4.
10. The Herald's and the Unmoored's lines.
