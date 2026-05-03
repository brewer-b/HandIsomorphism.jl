"""
    Recall

A management structure for hand indexing across multiple rounds, specifically designed to 
facilitate **imperfect recall**.

By storing a unique `Indexer` for each round's configuration, `Recall` allows the 
isomorphism logic to change as the game progresses (e.g., grouping previously distinct 
cards to reduce state-space complexity).
"""
struct Recall
    cards_per_round_per_round::Vector{Vector{UInt8}}
    indexers::Vector{Indexer}
    total_cards_per_round::Vector{Int}

    function Recall(cpr_per_round::Vector{<:AbstractVector{<:Integer}})
        n_rounds = length(cpr_per_round)
        indexers = Vector{Indexer}(undef, n_rounds)
        total_cards = Vector{Int}(undef, n_rounds)

        for i in 1:n_rounds
            cpr_tuple = Tuple(UInt8.(cpr_per_round[i]))
            indexers[i] = Indexer(cpr_tuple)
            total_cards[i] = sum(cpr_per_round[i])
        end

        return new(
            [Vector{UInt8}(v) for v in cpr_per_round],
            indexers,
            total_cards
        )
    end
end

"""
Returns the total number of unique isomorphic indices available at the specified `round`.
Useful for determining the size of regret or strategy arrays.
"""
@inline function round_size(recall::Recall, round)
    idxer = recall.indexers[round]
    return round_size(idxer, length(idxer.cards_per_round))
end

"""
Maps a specific collection of `cards` to its canonical isomorphic index for the given `round`.
The `cards` argument should be an iterable collection of card integers.
"""
@inline function index(recall::Recall, round, cards)
    return index(recall.indexers[round], cards)
end

"""
Performs the inverse of `index`. Takes a canonical `idx` and populates the `cards` 
buffer with a representative hand for that equivalence class at the specified `round`.
Returns `true` if the operation was successful.
"""
@inline function unindex(recall::Recall, round, idx, cards)
    idxer = recall.indexers[round]
    return unindex_all(idxer, length(idxer.cards_per_round), idx, cards)
end

"""
Returns the total number of cards expected by the indexer at a specific `round`. 
Use this to ensure your `cards` buffers are the correct size before calling `index` or `unindex`.
"""
@inline function cards_at_round(recall::Recall, round)
    return recall.total_cards_per_round[round]
end

const IMPERFECT_RECALL = Recall([[2], [2, 3], [2, 4], [2, 5]])
const PERFECT_RECALL = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 1, 1]])
const FLOP_RECALL = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 2]])
const BOARD_RECALL = Recall([[1], [3], [4], [5]])
