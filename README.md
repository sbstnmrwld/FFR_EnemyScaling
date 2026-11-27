# FFR_EnemyScaling

Enemy level scaling for **FINAL FANTASY RESONANCE**, as a [MogHub](https://github.com/jesus-seijas-sp/ffr-moghub) plugin.

No area becomes trivial. Every enemy and boss below your party's level is raised to it, and its stats, EXP and Gil grow to match. Enemies already at or above your level stay as they are.

## Features

| Setting | What it does | Default |
|---|---|---|
| **Scale normal enemies** | Normal enemies below the party level are raised to it. | On |
| **Scale bosses** | Bosses below the party level are raised to it: story and side bosses, strong foes, summons, the 12 Arms, Gilgamesh, Sephiroth, Ultima Weapon and the other superbosses. | On |
| **Party level** | The level enemies are raised to: the **highest**, **average** or **lowest** level of the current party. | Highest |
| **Level offset** | Added to the party level, from −5 to +10. With +3, every enemy is at least 3 levels above you. | 0 |
| **Scale EXP and Gil** | A raised enemy also gives the EXP and Gil of its new level. Item drops stay the same. | On |

- Enemies are only ever raised, never lowered.
- A raised enemy's stats (HP, break gauge, attack, defence, magic, spirit, speed) grow by the ratio of a typical vanilla enemy's stats at the old and the new level. An enemy that was tough for its level stays tough for its new level. Normal enemies and bosses each have their own curve.
- **Not scaled:** the Colosseum, the fights 700 years ago, and scripted fights you are meant to lose.
- The game's difficulty still applies on top: on Expert, enemies have 1.6× the HP and break gauge of the scaled values, as they would in vanilla.
- Changes happen on the map, never during a battle. Nothing is written into your save. When you remove the mod or switch it off, every enemy is back to the game's own values.

You change the settings in the game (main menu → **Mods** → **Enemy Scaling**), and they work with a controller. They are saved in `config.ini` next to the plugin.

Menu and messages are translated into English, German, French, Spanish, Japanese, Korean and Chinese (Simplified and Traditional).

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (tested with 4.0.0 experimental)
- [MogHub](https://github.com/jesus-seijas-sp/ffr-moghub) (tested with 1.0.1)

Do not use it together with another mod that changes enemy levels (such as Dynamic Boss Level Scaling). Both would rewrite the same rows.

## Installation

1. Install UE4SS and MogHub as their own instructions describe.
2. Download `FFR_EnemyScaling-<version>.zip` from the [latest release](https://github.com/sbstnmrwld/FFR_EnemyScaling/releases/latest) and extract it into
   `FINAL FANTASY RESONANCE\FFRS\Binaries\Win64\ue4ss\Mods\`
3. Start the game. The plugin appears under **Mods** in the main menu.

## How it works

- **Rows:** enemies come from the game's unit table `DT_UnitParameter`. On the map, the plugin rewrites the rows of enemies (category 2) and bosses (category 3 or `IsBoss`) in memory. A battle copies its enemies' rows when it starts. The original values are kept, so every change can be undone.
- **Party level:** `CPP_BFL_SaveDataParty.GetPartyUnitIdFromIndex` and `CPP_BFL_Unit.GetPlayableUnitLevel`.
- **Curves:** `curves.lua` holds the typical stat per level 1–99, fitted from all enemy rows of the game (`tools/curves.pl`, robust piecewise-linear fit of the log of each stat over level).
- **Excluded fights:** found in `DT_BattleGroup`: groups 700–799 (700 years ago), 9700–9799 (Colosseum ranks), the Colosseum's boss events, fights whose lose event is the same as their win event, and any fight on a Colosseum map. Enemies that appear only in such fights are never scaled. When such a fight starts with enemies it shares with other fights, all rows go back to the game's values for that battle (`CPP_BFL_Battle.GetEncountBattleGroupdId`).

## Known limitations

- **Colosseum not tested yet.** Leaving the Colosseum fights alone is built in, but it has not been checked in the game yet ([#1](https://github.com/sbstnmrwld/FFR_EnemyScaling/issues/1), [#2](https://github.com/sbstnmrwld/FFR_EnemyScaling/issues/2), [#3](https://github.com/sbstnmrwld/FFR_EnemyScaling/issues/3)). Some Colosseum fights may still be scaled until then.
- Enemy levels only change on the map. If your party levels up during a battle, the enemies of the next battle get the new level.

## Credits

Inspired by [Dynamic Boss Level Scaling](https://www.nexusmods.com/finalfantasyresonance/mods/307), which scales story bosses. This plugin is written from scratch: its own code, its own curves fitted from the game's data and its own choice of fights.

## AI disclosure

This mod was made by sbstnmrwld with the help of AI: [Claude Code](https://claude.com/claude-code) by Anthropic.

- **AI-generated:** the Lua code, the analysis of the game's data (which fights to leave alone, which enemies count as bosses), the stat curves and the script that fits them, the menu translations in `lang/`, this README and the texts of the issues and pull requests, written by Claude based on sbstnmrwld's design and requests.
- **Done by a human:** the feature design, decisions and testing in the game, all by sbstnmrwld.
- **Not included:** AI-generated images, audio, voices or models. The mod only uses the game's own data and visuals.

Commits made with AI help name Claude as co-author.

## License

[MIT](LICENSE): you may use, change and share this mod, also in your own mods, as long as the copyright notice is kept. Final Fantasy Resonance and all game data belong to their owners and are not covered by this license.
