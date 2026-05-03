"""
    Recall

A management structure for hand indexing across multiple rounds, specifically designed to 
facilitate **imperfect recall**.

By storing a unique `Indexer` for each round's configuration, `Recall` allows the 
isomorphism logic to change as the game progresses (e.g., grouping previously distinct 
cards to reduce state-space complexity).
"""
struct Recall{I1<:Indexer,I2<:Indexer,I3<:Indexer,I4<:Indexer}
    cards_per_round_per_round::NTuple{4,Vector{UInt8}}
    indexers::Tuple{I1,I2,I3,I4}
    total_cards_per_round::NTuple{4,Int}

    function Recall(cpr_per_round::Vector{<:AbstractVector{<:Integer}})
        length(cpr_per_round) == 4 || throw(ArgumentError("recall must contain four public rounds"))

        cards_per_round_per_round = (
            Vector{UInt8}(cpr_per_round[1]),
            Vector{UInt8}(cpr_per_round[2]),
            Vector{UInt8}(cpr_per_round[3]),
            Vector{UInt8}(cpr_per_round[4]),
        )
        indexers = (
            Indexer(Tuple(cards_per_round_per_round[1])),
            Indexer(Tuple(cards_per_round_per_round[2])),
            Indexer(Tuple(cards_per_round_per_round[3])),
            Indexer(Tuple(cards_per_round_per_round[4])),
        )
        total_cards = (
            sum(Int, cards_per_round_per_round[1]),
            sum(Int, cards_per_round_per_round[2]),
            sum(Int, cards_per_round_per_round[3]),
            sum(Int, cards_per_round_per_round[4]),
        )

        return new{typeof(indexers[1]),typeof(indexers[2]),typeof(indexers[3]),typeof(indexers[4])}(
            cards_per_round_per_round,
            indexers,
            total_cards
        )
    end
end

"""
Returns the total number of unique isomorphic indices available at the specified `round`.
Useful for determining the size of regret or strategy arrays.
"""
@inline function _round_size(indexer::Indexer)
    return round_size(indexer, length(indexer.cards_per_round))
end

@inline function round_size(recall::Recall, round::Integer)
    r = Int(round)
    if r == 1
        return _round_size(getfield(recall.indexers, 1))
    elseif r == 2
        return _round_size(getfield(recall.indexers, 2))
    elseif r == 3
        return _round_size(getfield(recall.indexers, 3))
    elseif r == 4
        return _round_size(getfield(recall.indexers, 4))
    else
        throw(BoundsError(recall.indexers, round))
    end
end

"""
Maps a specific collection of `cards` to its canonical isomorphic index for the given `round`.
The `cards` argument should be an iterable collection of card integers.
"""
@inline function index(recall::Recall, round::Integer, cards)
    r = Int(round)
    if r == 1
        return index(getfield(recall.indexers, 1), cards)
    elseif r == 2
        return index(getfield(recall.indexers, 2), cards)
    elseif r == 3
        return index(getfield(recall.indexers, 3), cards)
    elseif r == 4
        return index(getfield(recall.indexers, 4), cards)
    else
        throw(BoundsError(recall.indexers, round))
    end
end

"""
Performs the inverse of `index`. Takes a canonical `idx` and populates the `cards` 
buffer with a representative hand for that equivalence class at the specified `round`.
Returns `true` if the operation was successful.
"""
@inline function _unindex(indexer::Indexer, idx, cards)
    return unindex_all(indexer, length(indexer.cards_per_round), idx, cards)
end

@inline function unindex(recall::Recall, round::Integer, idx, cards)
    r = Int(round)
    if r == 1
        return _unindex(getfield(recall.indexers, 1), idx, cards)
    elseif r == 2
        return _unindex(getfield(recall.indexers, 2), idx, cards)
    elseif r == 3
        return _unindex(getfield(recall.indexers, 3), idx, cards)
    elseif r == 4
        return _unindex(getfield(recall.indexers, 4), idx, cards)
    else
        throw(BoundsError(recall.indexers, round))
    end
end

"""
Returns the total number of cards expected by the indexer at a specific `round`. 
Use this to ensure your `cards` buffers are the correct size before calling `index` or `unindex`.
"""
@inline function cards_at_round(recall::Recall, round::Integer)
    r = Int(round)
    if r == 1
        return getfield(recall.total_cards_per_round, 1)
    elseif r == 2
        return getfield(recall.total_cards_per_round, 2)
    elseif r == 3
        return getfield(recall.total_cards_per_round, 3)
    elseif r == 4
        return getfield(recall.total_cards_per_round, 4)
    else
        throw(BoundsError(recall.total_cards_per_round, round))
    end
end

const IMPERFECT_RECALL = Recall([[2], [2, 3], [2, 4], [2, 5]])
const PERFECT_RECALL = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 1, 1]])
const FLOP_RECALL = Recall([[2], [2, 3], [2, 3, 1], [2, 3, 2]])
const BOARD_RECALL = Recall([[1], [3], [4], [5]])
