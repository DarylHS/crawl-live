# P3 report: GDScript bot and data

Repo at main 0b91de2, Godot 4.7.2, 4 cores, nothing else running.

## Result

The GDScript bot reproduces the committed Phase 7 data byte for byte for seeds 0-1999. This is the P3 bar from `docs/port-plan.md` 11.3 decision 3, so the statistical fallback was not needed. No balance change arises from the port.

## Batch

Command: `python scripts/gd_bot.py --runs 2000 --workers 4 --no-events --out <scratch>` (200 shards of 10 seeds, one `godot --headless` process per shard).

| Item | Value |
|---|---|
| Wall time | 4,031 s (67.2 min); the script reports 4,024 s |
| Throughput | 0.50 runs/s overall, about 8.1 s of one core per run |
| Python reference | not re-timed here; the notebooks quote about 25 minutes for the same batch, so GDScript is roughly 2.7x slower |

The events table was not generated (`--no-events`, as for the committed files). Events parity was checked per seed in earlier slices (T6, seeds 0-39).

## CSV comparison

`python scripts/bot_csv_check.py <scratch> --seeds 0-1999` printed `BOT CSV OK: seeds 0-1999, 134590 rows in 5 files`, and `cmp` against `runs/bot_*.csv` agrees.

| Table | Rows (excl. header) | Bytes | Result |
|---|---|---|---|
| bot_runs.csv | 2,000 | 255,519 | identical |
| bot_floors.csv | 10,346 | 1,500,467 | identical |
| bot_boxes.csv | 7,130 | 663,326 | identical |
| bot_shop.csv | 75,114 | 3,855,806 | identical |
| bot_practice.csv | 40,000 | 1,144,032 | identical |
| bot_events.csv | not generated | n/a | not compared |

## Notebooks

The four notebooks in `analysis/` were run unchanged with `jupyter nbconvert --to notebook --execute --inplace` in a scratch copy of the repo (`analysis/`, `crawler/`, and `runs/` holding only the Godot CSVs). The notebooks find data through `ROOT/runs` in `analysis/common.py`, so a copy of the tree is all that is needed. The committed notebooks and `runs/` were not touched. Total execution time was 62 s, no errors.

I compared every stored output (text, tables, and the base64 PNG charts) with the committed notebooks' outputs. After masking only the random pandas Styler table ids and object addresses, all outputs are identical, including all 16 charts.

| Notebook | Key result (committed = Godot) | Outputs identical |
|---|---|---|
| 01 run analysis | 2,000 runs, 10,346 floor visits; victory 51.5% (1,030), killed 46.3% (926), collapse 2.2% (44); no-deal floors 5,397 with death rate 8.6%; levels vs turns correlation 0.95 | yes (24 outputs, 5 charts) |
| 02 loot boxes | 7,130 boxes in 832 runs; chi-square Bronze 5.82 (p 0.121), Silver 3.29 (p 0.349), Gold 4.26 (p 0.235), all consistent with stated odds; mean silver wait 6.0 | yes (26 outputs, 5 charts) |
| 03 shop forecasting | 75,114 item-floor rows; WAPE naive 79.3%, SES 0.3 67.5%, SES 0.1 66.1%; service level at z = 1: 88.4% bias-corrected, 84.7% shop today | yes (17 outputs, 3 charts) |
| 04 predict death | 10,346 floor visits, 9.4% deaths; test ROC AUC logistic 0.859, gradient boosting 0.850, base rate 0.500; honest 0.850, leaky 0.986, row-split 0.864 | yes (16 outputs, 3 charts) |

Death floors from the bot summary (same as committed, being the same data): floor 1 killed 57, floor 2 124, floor 3 134, floor 4 74, floor 5 210.

## Owner-pending balance items (restated, no change proposed)

The data is the Phase 7 data, so both items stand as before. By race, bog troll wins 76% (of 291) and houseplant 74% (of 325) against dwarf 44%, elf 48%, hobgoblin 46%, human 53%. By pet, mouse wins 42% (of 500) against cat 57%, budgie 54%, dog 53%.

## Conclusion

P3 is met at the strictest level: five of five tables byte-identical for 2,000 seeds, and all four notebooks reproduce their committed outputs exactly. The one gap is that the events table was not regenerated in this batch.
