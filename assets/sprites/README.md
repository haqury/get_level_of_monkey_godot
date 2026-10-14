# Sprites Structure

This directory contains all game sprites organized by category.

## Structure

### Player (`player/`)
- **idle/** - Idle animation (standing)
  - `down.png` - Standing sprite facing down
- **walk/** - Walking animations for 4 directions
  - `up.png`, `down.png`, `left.png`, `right.png`

### NPCs (`npc/`)
- `father.png` - Static sprite for Father NPC
- `mother.png` - Animated sprite for Mother NPC (cooking animation)
- **portraits/** - Dialog portraits (64x64)
  - `father.png`
  - `mother.png`

### Monkeys (`monkey/`)
- `age1.png`, `age2.png`, `age3.png`, `age4.png` - Base sprites for each age
- **run/** - Running animation sprites for each age
- **throw/** - Throwing animation sprites for each age

### Environment (`tiles/`)
- `floor.png` - Floor tile (32x32)
- `wall.png` - Wall tile with brick pattern (32x32)

### Kitchen (`kitchen/`)
- `stove.png` - Stove decoration
- `counter.png` - Kitchen counter
- `sink.png` - Kitchen sink

### Minigame (`minigame/`)
- `poop.png` - Projectile sprite (16x16)

## Generating Sprites

To regenerate all placeholder sprites, run:
```bash
python create_sprites.py
```

## Notes

- All sprites are currently placeholder sprites created programmatically
- Character sprites are 32x32 pixels
- Portrait sprites are 64x64 pixels
- Tiles are 32x32 pixels
- These can be replaced with custom artwork at any time
