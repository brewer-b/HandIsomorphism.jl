# HandIsomorphism.jl

`HandIsomorphism.jl` provides canonical isomorphism indices for poker hands across
betting rounds. The public API is built around `Recall` objects: choose a recall
scheme, then call `round_size`, `index`, `unindex`, and `cards_at_round`.

## Quick Start

```julia
using HandIsomorphism

cards = UInt8[1, 4, 9, 18, 23, 52, 47] # 2c, 2s, 4c, 6d, 7h, As, Ks

idx = index(PERFECT_RECALL, 4, cards)
size = round_size(PERFECT_RECALL, 4)

out = Vector{UInt8}(undef, cards_at_round(PERFECT_RECALL, 4))
ok = unindex(PERFECT_RECALL, 4, idx, out)
```

Indices are 1-based Julia integers. `unindex` fills `out` with one representative
hand from the isomorphism class and returns `true` when successful.

## Recall Presets

The package exports four ready-to-use recall schemes:

```julia
IMPERFECT_RECALL = Recall([[2], [2, 3], [2, 4], [2, 5]])
PERFECT_RECALL   = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 1, 1]])
FLOP_RECALL      = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 2]])
BOARD_RECALL     = Recall([[1], [3], [4], [5]])
```

Each inner vector describes the cards known to the indexer at that public round.
For example, `PERFECT_RECALL` uses two private cards preflop, then adds flop,
turn, and river cards as `2 + 3 + 1 + 1`.

`BOARD_RECALL` indexes board-only states. Its preflop entry is `[1]` because the
underlying indexer needs a first-round card group for its layout.

## API

```julia
round_size(recall, round)
```

Returns the number of canonical indices for `round`.

```julia
index(recall, round, cards)
```

Returns the canonical index for `cards` at `round`.

```julia
unindex(recall, round, idx, cards)
```

Writes a representative hand for `idx` into `cards` and returns whether the
operation succeeded.

```julia
cards_at_round(recall, round)
```

Returns the number of cards expected by the recall scheme at `round`.

## Card Encoding

Cards are encoded as integers from `1` to `52`, grouped by rank first and suit
second:

```text
1 = 2c, 2 = 2d, 3 = 2h, 4 = 2s
5 = 3c, ...
52 = As
```

Use `UInt8` vectors for compact storage and best performance.

## Testing

Run the test suite with:

```julia
using Pkg
Pkg.test()
```
