# Crawl Live! world bible (draft)

Status: first draft, built from what the game already contains. Companion to `docs/art-bible.md` (how things look); this file is what things *are* and *why*. Every new monster, item, line, floor or system should have a home here before it goes into the data files.

Each entry is tagged:

- **[Canon]** already in the game's data or text. Change it only on purpose.
- **[Proposed]** a suggestion from this draft. Not in the game yet; accept, change or cut.
- **[Open]** a question the owner needs to answer. Listed together in section 10.

## 1. Premise and pillars

**The one-line premise.** [Proposed] *Earth has been bought out of bankruptcy, and the dungeon is how the new owners strip it for parts. You are inventory. The show is how they make the stripping pay.*

What is already canon: Earth has been "repurposed", you are a contestant, floors collapse on a timer, billions are watching, and the ratings matter more than you do. [Canon]

The proposed premise keeps all of that and adds one idea that is ours, not the books': **the dungeon is a business, not just a broadcast.** The books are a game show run by sadists. Crawl Live! is a game show run by middle management. That is what the existing content already says (Shift Supervisor, Regional Manager, Bone Auditor, Aisle Nine, HR, Legal, the insurers), so the premise is catching up with the jokes rather than inventing new ones.

**Pillars.** Three tests every new piece of content should pass. [Proposed]

| Pillar | Means | Test for new content |
|---|---|---|
| The dungeon is grim, the show is loud | Real danger underneath, cheap showbiz bolted on top (from the art bible) | Does it have both a threat and a price tag? |
| Corporate satire, not cruelty | The villain is indifference, cost-cutting and spin. Comedy from props and paperwork, not gore | Could this joke appear in a real workplace memo? |
| The numbers are honest | Odds, forecasts and stats the game shows you are always true. Learning comes from decisions, never quizzes | Does the player learn something true by acting on it? |

**The core player fantasy.** [Proposed] Out-thinking a rigged system using its own rules. Not the strongest crawler, the one who read the fine print.

## 2. The rules of the world

This is the "physics" layer. Limits matter more than powers, so most of this section is about what the dungeon *cannot* do.

### 2.1 How the dungeon works

| Rule | Status | In-world reason |
|---|---|---|
| Six floors, each on a collapse timer (floor 1 is 12 hours, +1 hour per floor) | [Canon] | [Proposed] Each floor is a temporary build. Once it has been filmed it is demolished and its materials recycled into the next season. The timer is the demolition schedule. |
| Stairwells stay locked until half the floor's time has passed; a Headliner's key opens them early | [Canon] | [Proposed] Broadcast scheduling. The network needs a minimum runtime per episode; killing the Headliner ends the episode early, which the network tolerates because finales rate well. |
| Monsters respawn out of sight, more as the clock runs down | [Canon] | [Proposed] Cast call-backs. Extras are cheap and the producers pad the back half of every episode. |
| Safe rooms forbid violence | [Canon] | [Proposed] Workplace health and safety. Safe rooms are legally "studio hospitality", and the regulator (2.2) inspects them. |
| Loot boxes only from achievements and sponsors, opened only in safe rooms, odds always shown | [Canon] | [Proposed] Gambling regulation. Boxes count as prizes, prizes must be disclosed, and they can only be opened on licensed premises. |
| Race and class on floor 3 | [Canon] | [Proposed] Contestants who survive two episodes are "renewed" and given a character arc. Cheaper than writing one for everyone. |
| Monsters are a mix of fantasy creatures and repurposed Earth things (vacuum bots, supermarket rats) | [Canon] | [Proposed] Two supply lines. Fantasy monsters are licensed stock from a galactic catalogue, and the production buys the cheapest versions (hence *Knockoff* Goblin). Earth monsters are local materials "repurposed" on site, the same process being applied to the whole planet. |
| Loot is mostly Earth junk (frying pans, socks, half a trophy) | [Canon] | [Proposed] It is literally the planet's inventory. Everything you pick up has been catalogued and assigned a resale value, which is why the shop knows what it is worth. |

### 2.2 The System

[Canon] The narrator is "the System". Sarcastic, speaks as itself and as a corporate "we" (Legal, HR, the insurers, the producers). Sass is adjustable. It is "legally required" to show odds and "legally obliged" to congratulate you.

[Proposed] **The System is the compliance software, not the host.** The production would love a host who lies. Instead it is stuck with an AI that a galactic regulator requires on every licensed broadcast, to keep the contest within the rules and to disclose the truth to contestants. The System resents the producers, resents you, and resents its job, but it cannot lie about a number. That gives a reason for:

- the odds disclosure, Fun Facts and honest drop tables (it is legally bound to tell you the truth, and it does so as unhelpfully as possible);
- the snark (it can't stop the show, so it editorialises);
- the corporate "we" (it reads out notes from Legal, HR and the producers because it has to);
- the Analyst class (the one contestant the System grudgingly respects, because they actually read what it discloses).

[Proposed] **The regulator** is the *Bureau of Fair Odds*, an off-screen galactic standards body. It never appears in person. It is felt through the rules: safe rooms, disclosure, the timer minimums. Late in the game it is the one force that is on the player's side, slowly and bureaucratically.

## 3. Factions

Each faction gets the same five lines. That is the template for adding new ones.

| Faction | Status | Wants | Has | Method | Stance to the player |
|---|---|---|---|---|---|
| **The Production** (Executive Producer Glorm, the producers, writers, Legal, HR, accountants, merch) | Names [Canon], structure [Proposed] | Ratings at the lowest cost | The dungeon, the cast, the edit | Cost-cutting, padding, spin | You are content. Valuable while entertaining, expendable after |
| **The Consortium of Mild Concern** | [Canon] as the Legendary sponsor. [Proposed] as the owner | Return on the Earth acquisition | Earth, the network, everything | Asset-stripping; sponsors its own show to move money between its own subsidiaries | Never aware of you personally. You are a line item |
| **The System** | [Canon] | To get through the season with its compliance record clean | The rules, the odds, the microphone | Disclosure, sarcasm, malicious compliance | Hostile in tone, fair in fact. The only thing in the dungeon that never lies to you |
| **Sponsors** (Brightly Snacks, Gloop Energy, Vantage Mattress Co., Zorp Premium Hair Care) | [Canon] | Product placement | Gifts, contracts | Bribery dressed as opportunity: "+20% gold, but monsters hit harder" | Transactional. Help you when it sells product |
| **The Cast** (monsters, Opening and Featured Acts, Headliners) | [Canon] | [Proposed] To keep their jobs. Promotion from Opening Act to Featured to Headliner is a career ladder | Contracts, territory | Fighting you is literally their job description | Hostile because it's in their contract, not because they hate you |
| **The Hex Cult** (Hex Cultist, Cultist Influencer, Hex Cult Spokesperson, High Hexer Volka) | Names [Canon], belief [Proposed] | To be seen by the Audience | Devotion, numbers, free labour | They worship the ratings as a god ("the Watching"). Glorm uses them as unpaid security and extras | Zealous. You are either a saint (high viewers) or a heretic |
| **The Audience** | [Canon] as a number | To be entertained | The ratings, therefore everything | Attention, then boredom | Fickle. Your score, your safety net, your judge |
| **Other crawlers** | Referenced [Canon], absent until Phase 10 | To survive | Each other, maybe | Competition for stock, stairwells and screen time | [Open] Rivals, allies, or both? |
| **The Bureau of Fair Odds** | [Proposed] | Compliance | Licences, inspections, the System | Paperwork | Neutral, accidentally protective |

**Relationship map.** [Proposed] Who pulls on whom. Read across: how the row faction treats the column faction.

| | Production | Consortium | System | Sponsors | Cast | Cult | Bureau |
|---|---|---|---|---|---|---|---|
| **Production** | | Answers to, fears | Resents, can't fire | Courts | Exploits | Uses as free labour | Evades |
| **Consortium** | Owns | | Pays the licence for | Owns most of them | Doesn't know they exist | Doesn't know they exist | Lobbies |
| **System** | Reports on | Unaware of the full picture | | Discloses their terms | Referees | Finds tedious | Answers to |
| **Cult** | Worships Glorm as high priest | | Considers the System a prophet | Buys everything | Recruits from | | |

## 4. Places

### 4.1 The big picture

[Proposed] **The descent is a tour of the business.** Going down the dungeon means going up the org chart: from the drains, through records, construction, marketing and logistics, to the executive suite. Each floor is a department, each Headliner is its head, and the theme tells the player what that part of the company does to Earth.

### 4.2 Floors

Floor template: theme, department, Headliner, what the floor reveals, and the mechanic it leans on. Moods and set dressing are [Canon] from the art bible; departments and reveals are [Proposed].

| Floor | Set | Department | Headliner | What the player learns | Mechanic it leans on |
|---|---|---|---|---|---|
| 1 | Service tunnels and drains | Maintenance | The Grease Trap King | The basics. The show is cheap: it's built in Earth's sewers | Timer, safe rooms, first achievements |
| 2 | Archive stacks, card catalogues | Records | The Overdue Librarian | Everything on Earth has been catalogued and valued. The dungeon is an inventory | Loot, odds disclosure |
| 3 | Half-built site, scaffolding, hazard tape | Construction | Foreman Gristle | The floors are temporary builds, demolished after filming | Race and class (you've been "renewed") |
| 4 | Cult chapel doubling as a green room | Marketing and fan engagement | High Hexer Volka | The audience has its own believers, and the Production feeds on them | Viewers, sponsor contracts |
| 5 | Warehouse, pallets, cling film | Logistics | The Shrink-Wrapped Colossus | Earth is being packed and shipped. This is the payoff of floors 2 and 3 | Shop, stock, forecasting |
| 6 | Studio floor and executive suite | The executive | Executive Producer Glorm | Who profits, and how little you matter to them | Everything, plus the multi-phase finale |

### 4.3 Recurring places

| Place | Status | What it is |
|---|---|---|
| Safe rooms | [Canon] | "Studio hospitality". Pale green tiles, bed, bench, shop counter. [Proposed] Inspected by the Bureau, which is the only reason they're safe |
| Stairwells | [Canon] | Gold grates. [Proposed] Stage exits; the gold is set paint |
| The surface | Mentioned [Canon] | [Open] What is left up there? |
| Aisle Nine | Mentioned [Canon] | [Proposed] A supermarket swallowed whole into floor 1 or 2; home of the Rat Queen |

## 5. Characters

Character template: what they **want** (outward goal), what they **need** (what would actually change them), and their **line** (one sentence that captures the voice).

| Character | Status | Want | Need | Line |
|---|---|---|---|---|
| The player | [Canon] unnamed human, chosen backstory | Survive six floors | [Proposed] To stop playing for the audience and play for themselves | (theirs) |
| The System | [Canon] | A clean compliance record | [Proposed] Someone to admit it was right | "The System regrets nothing. The System would like that on the record." [Canon] |
| Executive Producer Glorm | [Canon] name, final boss | A hit season on budget | Never gets it | "Security! Get me SECURITY!" [Canon] |
| The Shadow Producer | [Canon] name | [Proposed] Glorm's line producer on the floor; edits the show live | | [Open] |
| High Hexer Volka | [Canon] name | [Proposed] To be noticed by the Audience she worships | | [Open] |
| The pet | [Canon] four species, named by the player | Each has its own vanity, loyalty or scheme | | Per-species quips [Canon] |

The other Headliners need the same three lines. They're placeholders until then.

## 6. History

Only what matters now. [Proposed] unless marked.

| When | What happened |
|---|---|
| Before | The Consortium of Mild Concern acquires Earth through a galactic insolvency process. [Open] Who sold it, and how? |
| The day of | "The world ended." [Canon] Earth is "repurposed" [Canon]: surface stripped, people sorted, the useful ones made contestants |
| Season 1 | Crawl Live! goes to air. The player is one of many crawlers [Canon]. Previous seasons on other planets are implied by the production's experience: [Open] |
| After floor 6 | "Escape confirmed. A sequel has been announced against your wishes." [Canon] |

## 7. Story arc

### 7.1 The season arc

[Proposed] One Story Circle across the six floors (Dan Harmon's eight steps: comfort, want, unfamiliar situation, adapt, get what you wanted, pay the price, return, changed).

| Step | Floor | Beat |
|---|---|---|
| 1. Comfort | Intro | Life before: the backstory you chose |
| 2. Want | 1 | Survive. Get out |
| 3. Unfamiliar situation | 1–2 | The rules, the System, the realisation that everything is catalogued |
| 4. Adapt | 3 | Race and class. You've been renewed; you start playing the game on purpose |
| 5. Get what you wanted | 4 | You're good now, popular even, and the Cult loves you for it |
| 6. Pay the price | 5 | The warehouse: you see what popularity is paying for. Earth, packed and shipped |
| 7. Return | 6 | Up to the executive suite to face the person in charge |
| 8. Changed | Victory | You escape, and the show renews you anyway. [Open] What has the player won? |

### 7.2 Each floor as an episode

[Proposed] Each floor runs its own small circle, which suits the timer: arrival (comfort), the Headliner's territory (unfamiliar), the safe room (adapt), the stairwell unlocking (get what you wanted), the clock running down and respawns rising (pay the price), the descent (changed).

### 7.3 Reveal ladder

What the player should learn, and when, so the lore arrives through play instead of text dumps. [Proposed]

| Floor | Reveal | Delivered through |
|---|---|---|
| 1 | The show is cheap | Knockoff Goblin, set dressing, System asides |
| 2 | Everything is inventory | Item descriptions with catalogue numbers and resale values |
| 3 | The floors are temporary | Demolition notices, scaffolding, Foreman Gristle |
| 4 | The Audience has believers | Cultists who cheer your viewer count |
| 5 | Earth is being shipped | Pallets of recognisable Earth things, shipping labels |
| 6 | The owner is the sponsor | Consortium branding in the executive suite |

## 8. Originality ledger

What is still close to *Dungeon Crawler Carl*, and the suggested action. The rule in `PHASES.md` is no names, characters, places or quotes, and the game meets it. These are the structures that still read as borrowed.

| Element | Status | Suggestion |
|---|---|---|
| "Crawler" for the player | [Canon] | Keep. It's a genre word now |
| "The System" as the sarcastic narrator | [Canon] | [Proposed] Keep the role, give it a proper name tied to compliance, so it isn't "the System AI". [Open] Name |
| "Safe room" | [Canon] | Keep in code; [Proposed] the in-world term becomes "Hospitality" on signage |
| Loot boxes in Bronze to Legendary tiers | [Canon] | Keep. The regulation angle makes them ours |
| Race and class on floor 3 | [Canon] | Keep the timing, justified by "renewal" (2.1) |
| Earth destroyed for an alien broadcast | [Canon] | Differentiated by the acquisition and asset-stripping premise (section 1) |
| The vain cat companion | [Canon] | Closest to a book character. [Proposed] Lean Mittens away from royalty and towards something else (an influencer? a cat convinced it's a sponsor?) |
| The five attributes | [Canon] | Shared with D&D anyway. Keep |

## 9. Parked ideas

Ideas worth keeping that don't fit yet.

**The refugee thread.** [Proposed] From the owner's half-remembered childhood book: a persecuted people, an escape through a hidden way, a journey through the roots of a great tree, coming out changed (hair colour) with two companions, facing something new. Possible fits:

- The Elf race is already playable. Elves could be refugees from an earlier repurposed world, "Season 1" of someone else's planet, living in the gaps between floors.
- A root network running between floors as secret passages: a way around the stairwell lock, at a cost.
- The transformation as a visible change to the character (hair, eyes) marking that they took the hidden way.
- Two companions mirrors the pet plus one other crawler, if Phase 10 adds allies.

Big enough to be its own spin-off or a Season 2. Decide once the main arc is settled.

## 10. Open questions for the owner

1. **Premise:** accept "the dungeon is a business; Earth is being asset-stripped"? This one decision shapes most of the rest.
2. **The System's name:** keep "the System", or give it one of its own?
3. **Who owns the show:** promote the Consortium of Mild Concern from sponsor to owner?
4. **Billions of viewers vs a count of 50:** [Proposed] the billions watch the show; the HUD number is *your* followers, the people watching your feed. Rename the HUD label to match?
5. **The surface:** is anyone left up there? (Lines mention "the folks back home" changing the channel.)
6. **Other crawlers:** rivals, allies, or both?
7. **Winning:** what does escape actually get you? A sequel is already announced.
8. **Previous seasons:** has the Consortium done this to other planets before?
9. **Headliners:** give each a want, a need and a line (section 5).
10. **The refugee thread:** spin-off, Season 2, or weave into this game?

## How to use this file

- New content gets a slot here before it goes into `crawler/` data or `godot/data/`: a faction gets the five-line row, a floor gets the floor row, a character gets want / need / line.
- When an [Open] question is answered, update the entry and change its tag. When a [Proposed] item goes into the game, change it to [Canon].
- Text in game takes its voice from section 1's pillars and the System's rules in 2.2.
