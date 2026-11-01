# Sound Attribution

Every bundled sample is MIT-licensed or original work. Each pack folder under
`Resources/Sounds/` carries its own `LICENSE` copy.

| Pack | Actual switch recorded | Source | License |
|---|---|---|---|
| Japanese Black | Gateron Black Ink | [tplai/kbsim](https://github.com/tplai/kbsim) `blackink` | MIT (Thomas Lai) |
| Cream | NovelKeys Cream | [tplai/kbsim](https://github.com/tplai/kbsim) `cream` | MIT (Thomas Lai) |
| Holy Panda | Holy Panda | [tplai/kbsim](https://github.com/tplai/kbsim) `holypanda` | MIT (Thomas Lai) |
| Super Red | Gateron Red Ink | [tplai/kbsim](https://github.com/tplai/kbsim) `redink` | MIT (Thomas Lai) |
| Milky Yellow | Alpaca linear (stand-in¹) | [tplai/kbsim](https://github.com/tplai/kbsim) `alpaca` | MIT (Thomas Lai) |
| Cardboard | Topre (dampened stand-in¹) | [tplai/kbsim](https://github.com/tplai/kbsim) `topre` | MIT (Thomas Lai) |
| Oreo | Everglide Oreo | [hainguyents13/mechvibes](https://github.com/hainguyents13/mechvibes) `eg-oreo`, sliced from its sprite per `config.json` offsets | MIT (Nguyen Hai) |
| Return ding | — | Synthesized additively by `scripts/build_sounds.py` | MIT (this project) |
| Mouse clicks | — | Synthesized by `scripts/build_sounds.py` | MIT (this project) |

¹ No permissively-licensed recording of the actual switch (Gateron Milky
Yellow / Klack's "Cardboard" set) exists that we could find. These two packs
use the closest-sounding MIT-licensed sets: Alpaca (deep smooth linear) and
Topre (dampened thock). PRs with clean recordings of the real switches are
welcome.

The catalog is fully reproducible: `make sounds` re-downloads and rebuilds
everything from the upstream repos.

Do **not** add sound packs from mechvibes.com community uploads, YouTube rips,
or other unlicensed sources.
