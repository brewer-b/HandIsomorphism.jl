module HandIsomorphism

export Recall,
    IMPERFECT_RECALL,
    PERFECT_RECALL,
    FLOP_RECALL,
    BOARD_RECALL,
    round_size,
    index,
    unindex!,
    cards_at_round

const SUITS = 4
const RANKS = 13
const CARDS = 52
const MAX_ROUNDS = 8
const ROUND_SHIFT = 4
const ROUND_MASK = UInt32(0x0f)

const HandIndex = UInt64

struct Indexer{R}
    cards_per_round::NTuple{R,UInt8}
    round_start::NTuple{R,UInt8}
    sizes::NTuple{R,HandIndex}
    configurations::NTuple{R,UInt32}
    permutations::NTuple{R,UInt32}
    permutation_to_configuration::NTuple{R,Vector{UInt32}}
    permutation_to_pi::NTuple{R,Vector{UInt8}}
    configuration_to_equal::NTuple{R,Vector{UInt8}}
    configuration_to_offset::NTuple{R,Vector{HandIndex}}
    configuration::NTuple{R,Vector{UInt32}}
    configuration_to_suit_size::NTuple{R,Vector{UInt32}}
end

function Indexer(cards_per_round::NTuple{R,<:Integer}) where {R}
    _check_rounds(cards_per_round)

    cpr = ntuple(i -> UInt8(cards_per_round[i]), Val(R))
    starts = _round_starts(cpr)

    configurations_by_round = ntuple(_ -> Vector{NTuple{SUITS,UInt32}}(), Val(R))
    _enumerate_configurations!(configurations_by_round, cpr)
    foreach(sort!, configurations_by_round)

    configuration_counts = ntuple(i -> UInt32(length(configurations_by_round[i])), Val(R))
    configuration_maps = ntuple(i -> _configuration_map(configurations_by_round[i]), Val(R))

    configuration = ntuple(i -> Vector{UInt32}(undef, SUITS * length(configurations_by_round[i])), Val(R))
    configuration_to_equal = ntuple(i -> Vector{UInt8}(undef, length(configurations_by_round[i])), Val(R))
    configuration_to_offset = ntuple(i -> Vector{HandIndex}(undef, length(configurations_by_round[i])), Val(R))
    configuration_to_suit_size = ntuple(i -> Vector{UInt32}(undef, SUITS * length(configurations_by_round[i])), Val(R))
    sizes_work = Vector{HandIndex}(undef, R)

    for round in 1:R
        configs = configurations_by_round[round]
        cfg_flat = configuration[round]
        equal = configuration_to_equal[round]
        offset = configuration_to_offset[round]
        suit_size = configuration_to_suit_size[round]

        for id in eachindex(configs)
            cfg = configs[id]
            base = _cfgbase(id)
            cfg_flat[base + 1] = cfg[1]
            cfg_flat[base + 2] = cfg[2]
            cfg_flat[base + 3] = cfg[3]
            cfg_flat[base + 4] = cfg[4]

            product = HandIndex(1)
            equal_bits = UInt32(0)
            suit = 1
            while suit <= SUITS
                group_size = _suit_configuration_size(cfg[suit], round, R)
                next_suit = suit + 1
                while next_suit <= SUITS && cfg[next_suit] == cfg[suit]
                    next_suit += 1
                end

                group_len = next_suit - suit
                for group_suit in suit:(next_suit - 1)
                    suit_size[base + group_suit] = UInt32(group_size)
                end
                product *= _ncr_group(group_size + HandIndex(group_len - 1), group_len)

                for group_suit in (suit + 1):(next_suit - 1)
                    equal_bits |= UInt32(1) << (group_suit - 1)
                end

                suit = next_suit
            end

            offset[id] = product
            equal[id] = UInt8(equal_bits >> 1)
        end

        accum = HandIndex(0)
        for id in eachindex(offset)
            next_accum = accum + offset[id]
            offset[id] = accum
            accum = next_accum
        end
        sizes_work[round] = accum
    end
    round_sizes = ntuple(i -> sizes_work[i], Val(R))

    permutations_by_round = ntuple(_ -> Vector{NTuple{SUITS,UInt32}}(), Val(R))
    _enumerate_permutations!(permutations_by_round, cpr)

    permutation_counts_work = fill(UInt32(0), R)
    for round in 1:R
        for count in permutations_by_round[round]
            idx = _permutation_index(cpr, count, round, R)
            needed = UInt32(idx + 1)
            if permutation_counts_work[round] < needed
                permutation_counts_work[round] = needed
            end
        end
    end
    permutation_counts = ntuple(i -> permutation_counts_work[i], Val(R))

    permutation_to_configuration = ntuple(i -> fill(UInt32(0), Int(permutation_counts[i])), Val(R))
    permutation_to_pi = ntuple(i -> fill(UInt8(0), Int(permutation_counts[i])), Val(R))

    for round in 1:R
        perm_to_config = permutation_to_configuration[round]
        perm_to_pi = permutation_to_pi[round]
        config_map = configuration_maps[round]

        for count in permutations_by_round[round]
            idx = _permutation_index(cpr, count, round, R)
            pi, pi_index = _sorted_suit_permutation(count)
            perm_to_config[idx + 1] = config_map[(count[pi[1] + 1], count[pi[2] + 1], count[pi[3] + 1], count[pi[4] + 1])]
            perm_to_pi[idx + 1] = UInt8(pi_index)
        end
    end

    return Indexer{R}(
        cpr,
        starts,
        round_sizes,
        configuration_counts,
        permutation_counts,
        permutation_to_configuration,
        permutation_to_pi,
        configuration_to_equal,
        configuration_to_offset,
        configuration,
        configuration_to_suit_size,
    )
end

Indexer(cards_per_round::AbstractVector{<:Integer}) = Indexer(Tuple(cards_per_round))

@inline round_size(indexer::Indexer, round::Integer) = @inbounds indexer.sizes[Int(round)]

@inline index(indexer::Indexer, cards) = _index(indexer, cards, nothing)

@inline index(indexer::Indexer, cards, indices) = _index(indexer, cards, indices)

function _unindex_all(indexer::Indexer{R}, round::Integer, idx::Integer, cards) where {R}
    public_round = Int(round)
    if public_round < 1 || public_round > R || idx < 1
        return false
    end

    limit = @inbounds indexer.sizes[public_round]
    if idx > limit
        return false
    end

    zero_based_index = HandIndex(idx - 1)

    @inbounds begin
        offsets = indexer.configuration_to_offset[public_round]
        configuration_count = Int(indexer.configurations[public_round])

        low = 1
        high = configuration_count + 1
        configuration_idx = 1
        while low < high
            mid = (low + high) >>> 1
            if offsets[mid] <= zero_based_index
                configuration_idx = mid
                low = mid + 1
            else
                high = mid
            end
        end

        zero_based_index -= offsets[configuration_idx]

        cfg = indexer.configuration[public_round]
        suit_size = indexer.configuration_to_suit_size[public_round]
        base = _cfgbase(configuration_idx)

        suit_index_0 = HandIndex(0)
        suit_index_1 = HandIndex(0)
        suit_index_2 = HandIndex(0)
        suit_index_3 = HandIndex(0)

        suit = 0
        while suit < SUITS
            next_suit = suit + 1
            while next_suit < SUITS && cfg[base + next_suit + 1] == cfg[base + suit + 1]
                next_suit += 1
            end

            len = next_suit - suit
            this_suit_size = HandIndex(suit_size[base + suit + 1])
            group_size = _ncr_group(this_suit_size + HandIndex(len - 1), len)
            group_index = zero_based_index % group_size
            zero_based_index ÷= group_size

            if len == 4
                x0 = _unrank_group_prefix(group_index, this_suit_size, 4)
                group_index -= _ncr_group(x0 + 3, 4)
                x1 = _unrank_group_prefix(group_index, this_suit_size, 3)
                group_index -= _ncr_group(x1 + 2, 3)
                x2 = _unrank_group_prefix(group_index, this_suit_size, 2)
                group_index -= _ncr_group(x2 + 1, 2)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit, x0)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 1, x1)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 2, x2)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 3, group_index)
            elseif len == 3
                x0 = _unrank_group_prefix(group_index, this_suit_size, 3)
                group_index -= _ncr_group(x0 + 2, 3)
                x1 = _unrank_group_prefix(group_index, this_suit_size, 2)
                group_index -= _ncr_group(x1 + 1, 2)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit, x0)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 1, x1)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 2, group_index)
            elseif len == 2
                x0 = _unrank_group_prefix(group_index, this_suit_size, 2)
                group_index -= _ncr_group(x0 + 1, 2)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit, x0)
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 1, group_index)
            else
                suit_index_0, suit_index_1, suit_index_2, suit_index_3 =
                    _set4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit, group_index)
            end

            suit = next_suit
        end

        _unindex_suit!(cards, indexer, cfg, base, 0, suit_index_0)
        _unindex_suit!(cards, indexer, cfg, base, 1, suit_index_1)
        _unindex_suit!(cards, indexer, cfg, base, 2, suit_index_2)
        _unindex_suit!(cards, indexer, cfg, base, 3, suit_index_3)
    end

    return true
end

function _check_rounds(cards_per_round::NTuple{R,<:Integer}) where {R}
    if R == 0 || R > MAX_ROUNDS
        throw(ArgumentError("round count must be in 1:$MAX_ROUNDS"))
    end

    total = 0
    for cards in cards_per_round
        if cards < 0
            throw(ArgumentError("cards per round must be non-negative"))
        end
        total += cards
        if total > CARDS
            throw(ArgumentError("total cards cannot exceed $CARDS"))
        end
    end

    return nothing
end

function _round_starts(cards_per_round::NTuple{R,UInt8}) where {R}
    start = 1
    return ntuple(Val(R)) do i
        this_start = start
        start += Int(cards_per_round[i])
        UInt8(this_start)
    end
end

function _configuration_map(configurations::Vector{NTuple{SUITS,UInt32}})
    map = Dict{NTuple{SUITS,UInt32},UInt32}()
    sizehint!(map, length(configurations))
    for i in eachindex(configurations)
        map[configurations[i]] = UInt32(i)
    end
    return map
end

function _enumerate_configurations!(out::NTuple{R,Vector{NTuple{SUITS,UInt32}}}, cards_per_round::NTuple{R,UInt8}) where {R}
    used = zeros(Int, SUITS)
    configuration = zeros(UInt32, SUITS)
    _enumerate_configurations_r!(out, cards_per_round, 1, Int(cards_per_round[1]), 0, (1 << SUITS) - 2, used, configuration)
    return out
end

function _enumerate_configurations_r!(
    out::NTuple{R,Vector{NTuple{SUITS,UInt32}}},
    cards_per_round::NTuple{R,UInt8},
    round::Int,
    remaining::Int,
    suit::Int,
    equal::Int,
    used::Vector{Int},
    configuration::Vector{UInt32},
) where {R}
    if suit == SUITS
        push!(out[round], (configuration[1], configuration[2], configuration[3], configuration[4]))

        if round < R
            _enumerate_configurations_r!(out, cards_per_round, round + 1, Int(cards_per_round[round + 1]), 0, equal, used, configuration)
        end
    else
        min_cards = suit == SUITS - 1 ? remaining : 0
        max_cards = min(RANKS - used[suit + 1], remaining)

        was_equal = (equal & (1 << suit)) != 0
        previous = RANKS + 1
        if was_equal
            shift = ROUND_SHIFT * (R - round)
            previous = Int((configuration[suit] >> shift) & ROUND_MASK)
            if previous < max_cards
                max_cards = previous
            end
        end

        old_configuration = configuration[suit + 1]
        old_used = used[suit + 1]
        shift = ROUND_SHIFT * (R - round)
        for cards in min_cards:max_cards
            new_configuration = old_configuration | (UInt32(cards) << shift)
            new_equal = (equal & ~(1 << suit)) | ((was_equal && cards == previous) ? (1 << suit) : 0)

            used[suit + 1] = old_used + cards
            configuration[suit + 1] = new_configuration
            _enumerate_configurations_r!(out, cards_per_round, round, remaining - cards, suit + 1, new_equal, used, configuration)
            configuration[suit + 1] = old_configuration
            used[suit + 1] = old_used
        end
    end

    return nothing
end

function _enumerate_permutations!(out::NTuple{R,Vector{NTuple{SUITS,UInt32}}}, cards_per_round::NTuple{R,UInt8}) where {R}
    used = zeros(Int, SUITS)
    count = zeros(UInt32, SUITS)
    _enumerate_permutations_r!(out, cards_per_round, 1, Int(cards_per_round[1]), 0, used, count)
    return out
end

function _enumerate_permutations_r!(
    out::NTuple{R,Vector{NTuple{SUITS,UInt32}}},
    cards_per_round::NTuple{R,UInt8},
    round::Int,
    remaining::Int,
    suit::Int,
    used::Vector{Int},
    count::Vector{UInt32},
) where {R}
    if suit == SUITS
        push!(out[round], (count[1], count[2], count[3], count[4]))

        if round < R
            _enumerate_permutations_r!(out, cards_per_round, round + 1, Int(cards_per_round[round + 1]), 0, used, count)
        end
    else
        min_cards = suit == SUITS - 1 ? remaining : 0
        max_cards = min(RANKS - used[suit + 1], remaining)

        old_count = count[suit + 1]
        old_used = used[suit + 1]
        shift = ROUND_SHIFT * (R - round)
        for cards in min_cards:max_cards
            new_count = old_count | (UInt32(cards) << shift)

            used[suit + 1] = old_used + cards
            count[suit + 1] = new_count
            _enumerate_permutations_r!(out, cards_per_round, round, remaining - cards, suit + 1, used, count)
            count[suit + 1] = old_count
            used[suit + 1] = old_used
        end
    end

    return nothing
end

@inline _cfgbase(id::Integer) = (Int(id) - 1) * SUITS

function _suit_configuration_size(configuration::UInt32, round::Int, rounds::Int)
    size = HandIndex(1)
    remaining = RANKS
    for j in 1:round
        ranks = Int((configuration >> (ROUND_SHIFT * (rounds - j))) & ROUND_MASK)
        size *= HandIndex(NCR_RANKS[remaining + 1, ranks + 1])
        remaining -= ranks
    end
    return size
end

function _permutation_index(cards_per_round::NTuple{R,UInt8}, count::NTuple{SUITS,UInt32}, round::Int, rounds::Int) where {R}
    idx = 0
    mult = 1
    for i in 1:round
        remaining = Int(cards_per_round[i])
        shift = ROUND_SHIFT * (rounds - i)
        for suit in 1:(SUITS - 1)
            size = Int((count[suit] >> shift) & ROUND_MASK)
            idx += mult * size
            mult *= remaining + 1
            remaining -= size
        end
    end
    return idx
end

function _sorted_suit_permutation(count::NTuple{SUITS,UInt32})
    pi0 = 0
    pi1 = 1
    pi2 = 2
    pi3 = 3

    if count[pi1 + 1] > count[pi0 + 1]
        pi0, pi1 = pi1, pi0
    end
    if count[pi2 + 1] > count[pi1 + 1]
        pi1, pi2 = pi2, pi1
        if count[pi1 + 1] > count[pi0 + 1]
            pi0, pi1 = pi1, pi0
        end
    end
    if count[pi3 + 1] > count[pi2 + 1]
        pi2, pi3 = pi3, pi2
        if count[pi2 + 1] > count[pi1 + 1]
            pi1, pi2 = pi2, pi1
            if count[pi1 + 1] > count[pi0 + 1]
                pi0, pi1 = pi1, pi0
            end
        end
    end

    pi_index = _permutation_to_index(pi0, pi1, pi2, pi3)
    return (pi0, pi1, pi2, pi3), pi_index
end

function _permutation_to_index(pi0::Int, pi1::Int, pi2::Int, pi3::Int)
    idx = 0
    mult = 1
    used = 0

    bit = 1 << pi0
    idx += (pi0 - count_ones((bit - 1) & used)) * mult
    mult *= 4
    used |= bit

    bit = 1 << pi1
    idx += (pi1 - count_ones((bit - 1) & used)) * mult
    mult *= 3
    used |= bit

    bit = 1 << pi2
    idx += (pi2 - count_ones((bit - 1) & used)) * mult
    mult *= 2
    used |= bit

    bit = 1 << pi3
    idx += (pi3 - count_ones((bit - 1) & used)) * mult

    return idx
end

function _index(indexer::Indexer{R}, cards, indices) where {R}
    suit_index_0 = HandIndex(0)
    suit_index_1 = HandIndex(0)
    suit_index_2 = HandIndex(0)
    suit_index_3 = HandIndex(0)

    suit_multiplier_0 = HandIndex(1)
    suit_multiplier_1 = HandIndex(1)
    suit_multiplier_2 = HandIndex(1)
    suit_multiplier_3 = HandIndex(1)

    used_ranks_0 = UInt32(0)
    used_ranks_1 = UInt32(0)
    used_ranks_2 = UInt32(0)
    used_ranks_3 = UInt32(0)

    permutation_index = UInt32(0)
    permutation_multiplier = UInt32(1)

    card_offset = 1
    result = HandIndex(0)

    @inbounds for round in 1:R
        ranks_0 = UInt32(0)
        ranks_1 = UInt32(0)
        ranks_2 = UInt32(0)
        ranks_3 = UInt32(0)

        shifted_ranks_0 = UInt32(0)
        shifted_ranks_1 = UInt32(0)
        shifted_ranks_2 = UInt32(0)
        shifted_ranks_3 = UInt32(0)

        for _ in 1:Int(indexer.cards_per_round[round])
            card = UInt32(cards[card_offset]) - UInt32(1)
            card_offset += 1

            suit = Int(card & UInt32(0x03))
            rank = Int(card >> 2)
            rank_bit = UInt32(1) << rank

            if suit == 0
                ranks_0 |= rank_bit
                shifted_ranks_0 |= rank_bit >> count_ones((rank_bit - UInt32(1)) & used_ranks_0)
            elseif suit == 1
                ranks_1 |= rank_bit
                shifted_ranks_1 |= rank_bit >> count_ones((rank_bit - UInt32(1)) & used_ranks_1)
            elseif suit == 2
                ranks_2 |= rank_bit
                shifted_ranks_2 |= rank_bit >> count_ones((rank_bit - UInt32(1)) & used_ranks_2)
            else
                ranks_3 |= rank_bit
                shifted_ranks_3 |= rank_bit >> count_ones((rank_bit - UInt32(1)) & used_ranks_3)
            end
        end

        this_size_0 = UInt32(count_ones(ranks_0))
        this_size_1 = UInt32(count_ones(ranks_1))
        this_size_2 = UInt32(count_ones(ranks_2))
        this_size_3 = UInt32(count_ones(ranks_3))

        used_size_0 = count_ones(used_ranks_0)
        used_size_1 = count_ones(used_ranks_1)
        used_size_2 = count_ones(used_ranks_2)
        used_size_3 = count_ones(used_ranks_3)

        suit_index_0 += suit_multiplier_0 * HandIndex(RANK_SET_TO_INDEX[Int(shifted_ranks_0) + 1])
        suit_index_1 += suit_multiplier_1 * HandIndex(RANK_SET_TO_INDEX[Int(shifted_ranks_1) + 1])
        suit_index_2 += suit_multiplier_2 * HandIndex(RANK_SET_TO_INDEX[Int(shifted_ranks_2) + 1])
        suit_index_3 += suit_multiplier_3 * HandIndex(RANK_SET_TO_INDEX[Int(shifted_ranks_3) + 1])

        suit_multiplier_0 *= HandIndex(NCR_RANKS[RANKS - used_size_0 + 1, Int(this_size_0) + 1])
        suit_multiplier_1 *= HandIndex(NCR_RANKS[RANKS - used_size_1 + 1, Int(this_size_1) + 1])
        suit_multiplier_2 *= HandIndex(NCR_RANKS[RANKS - used_size_2 + 1, Int(this_size_2) + 1])
        suit_multiplier_3 *= HandIndex(NCR_RANKS[RANKS - used_size_3 + 1, Int(this_size_3) + 1])

        used_ranks_0 |= ranks_0
        used_ranks_1 |= ranks_1
        used_ranks_2 |= ranks_2
        used_ranks_3 |= ranks_3

        remaining = UInt32(indexer.cards_per_round[round])
        permutation_index += permutation_multiplier * this_size_0
        permutation_multiplier *= remaining + UInt32(1)
        remaining -= this_size_0
        permutation_index += permutation_multiplier * this_size_1
        permutation_multiplier *= remaining + UInt32(1)
        remaining -= this_size_1
        permutation_index += permutation_multiplier * this_size_2
        permutation_multiplier *= remaining + UInt32(1)

        lookup = Int(permutation_index) + 1
        configuration = indexer.permutation_to_configuration[round][lookup]
        pi_index = indexer.permutation_to_pi[round][lookup]
        equal_index = indexer.configuration_to_equal[round][Int(configuration)]
        offset = indexer.configuration_to_offset[round][Int(configuration)]

        permutation = SUIT_PERMUTATIONS[Int(pi_index) + 1]

        pi0 = Int(permutation[1])
        pi1 = Int(permutation[2])
        pi2 = Int(permutation[3])
        pi3 = Int(permutation[4])

        permuted_suit_index_0 = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, pi0)
        permuted_suit_index_1 = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, pi1)
        permuted_suit_index_2 = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, pi2)
        permuted_suit_index_3 = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, pi3)

        permuted_suit_multiplier_0 = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, pi0)
        permuted_suit_multiplier_1 = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, pi1)
        permuted_suit_multiplier_2 = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, pi2)
        permuted_suit_multiplier_3 = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, pi3)

        result = _round_index(
            offset,
            equal_index,
            permuted_suit_index_0,
            permuted_suit_index_1,
            permuted_suit_index_2,
            permuted_suit_index_3,
            permuted_suit_multiplier_0,
            permuted_suit_multiplier_1,
            permuted_suit_multiplier_2,
            permuted_suit_multiplier_3,
        )

        _store_index!(indices, round, result + HandIndex(1))
    end

    return result + HandIndex(1)
end

@inline _store_index!(::Nothing, round::Int, value::HandIndex) = nothing

@inline function _store_index!(indices, round::Int, value::HandIndex)
    @inbounds indices[round] = value
    return nothing
end

@inline function _round_index(
    offset::HandIndex,
    equal_index::UInt8,
    suit_index_0::HandIndex,
    suit_index_1::HandIndex,
    suit_index_2::HandIndex,
    suit_index_3::HandIndex,
    suit_multiplier_0::HandIndex,
    suit_multiplier_1::HandIndex,
    suit_multiplier_2::HandIndex,
    suit_multiplier_3::HandIndex,
)
    idx = offset
    multiplier = HandIndex(1)
    suit = 0
    while suit < SUITS
        len = _equal_run_length(equal_index, suit)

        part, size = if len == 4
            a = suit_index_0
            b = suit_index_1
            c = suit_index_2
            d = suit_index_3
            a, b = _sort2(a, b)
            c, d = _sort2(c, d)
            a, c = _sort2(a, c)
            b, d = _sort2(b, d)
            b, c = _sort2(b, c)

            (
                a + _ncr2(b + 1) + _ncr3(c + 2) + _ncr4(d + 3),
                _ncr4(suit_multiplier_0 + 3),
            )
        elseif len == 3
            a = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit)
            b = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 1)
            c = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 2)
            a, b = _sort2(a, b)
            a, c = _sort2(a, c)
            b, c = _sort2(b, c)

            m = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, suit)
            (
                a + _ncr2(b + 1) + _ncr3(c + 2),
                _ncr3(m + 2),
            )
        elseif len == 2
            a = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit)
            b = _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit + 1)
            a, b = _sort2(a, b)

            m = _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, suit)
            (
                a + _ncr2(b + 1),
                _ncr2(m + 1),
            )
        else
            (
                _get4(suit_index_0, suit_index_1, suit_index_2, suit_index_3, suit),
                _get4(suit_multiplier_0, suit_multiplier_1, suit_multiplier_2, suit_multiplier_3, suit),
            )
        end

        idx += multiplier * part
        multiplier *= size
        suit += len
    end

    return idx
end

@inline function _equal_run_length(equal_index::UInt8, suit::Int)
    if suit < 3 && (Int(equal_index) & (1 << suit)) != 0
        if suit < 2 && (Int(equal_index) & (1 << (suit + 1))) != 0
            if suit < 1 && (Int(equal_index) & (1 << (suit + 2))) != 0
                return 4
            end
            return 3
        end
        return 2
    end
    return 1
end

@inline _sort2(a::HandIndex, b::HandIndex) = ifelse(a > b, (b, a), (a, b))

@inline function _get4(a, b, c, d, idx::Int)
    return idx == 0 ? a : idx == 1 ? b : idx == 2 ? c : d
end

@inline function _set4(a::HandIndex, b::HandIndex, c::HandIndex, d::HandIndex, idx::Int, value::HandIndex)
    return idx == 0 ? (value, b, c, d) :
           idx == 1 ? (a, value, c, d) :
           idx == 2 ? (a, b, value, d) :
                      (a, b, c, value)
end

@inline _ncr2(n::HandIndex) = (n * (n - 1)) ÷ 2

@inline _ncr3(n::HandIndex) = (n * (n - 1) * (n - 2)) ÷ 6

@inline _ncr4(n::HandIndex) = (n * (n - 1) * (n - 2) * (n - 3)) ÷ 24

@inline function _ncr_group(n::HandIndex, k::Int)
    return k == 0 ? HandIndex(1) :
           k == 1 ? n :
           k == 2 ? _ncr2(n) :
           k == 3 ? _ncr3(n) :
                    _ncr4(n)
end

function _unrank_group_prefix(group_index::HandIndex, suit_size::HandIndex, k::Int)
    low = HandIndex(0)
    high = suit_size
    best = HandIndex(0)

    while low < high
        mid = (low + high) >>> 1
        if _ncr_group(mid + HandIndex(k - 1), k) <= group_index
            best = mid
            low = mid + 1
        else
            high = mid
        end
    end

    return best
end

function _unindex_suit!(cards, indexer::Indexer{R}, cfg::Vector{UInt32}, base::Int, suit::Int, suit_index::HandIndex) where {R}
    used = UInt32(0)
    m = 0

    @inbounds for round in 1:R
        shift = ROUND_SHIFT * (R - round)
        n = Int((cfg[base + suit + 1] >> shift) & ROUND_MASK)
        round_size = HandIndex(NCR_RANKS[RANKS - m + 1, n + 1])
        m += n

        round_index = suit_index % round_size
        suit_index ÷= round_size

        shifted_cards = INDEX_TO_RANK_SET[n + 1, Int(round_index) + 1]
        rank_set = UInt32(0)
        location = _round_suit_location(indexer, cfg, base, round, suit)

        for _ in 1:n
            shifted_card = shifted_cards & (zero(UInt32) - shifted_cards)
            shifted_cards ⊻= shifted_card

            rank = NTH_UNSET[Int(used) + 1, trailing_zeros(shifted_card) + 1]
            rank_bit = UInt32(1) << Int(rank)
            rank_set |= rank_bit

            cards[location] = _make_card(suit, Int(rank))
            location += 1
        end

        used |= rank_set
    end

    return nothing
end

@inline function _round_suit_location(indexer::Indexer{R}, cfg::Vector{UInt32}, base::Int, round::Int, suit::Int) where {R}
    shift = ROUND_SHIFT * (R - round)
    location = Int(indexer.round_start[round])
    previous_suit = 0
    while previous_suit < suit
        location += Int((cfg[base + previous_suit + 1] >> shift) & ROUND_MASK)
        previous_suit += 1
    end
    return location
end

@inline _make_card(suit::Int, rank::Int) = UInt8(rank * SUITS + suit + 1)

function _make_nth_unset()
    table = Matrix{UInt8}(undef, 1 << RANKS, RANKS)
    full = UInt32((1 << RANKS) - 1)
    for mask in 0:((1 << RANKS) - 1)
        set = (~UInt32(mask)) & full
        for n in 0:(RANKS - 1)
            if set == 0
                table[mask + 1, n + 1] = 0xff
            else
                table[mask + 1, n + 1] = UInt8(trailing_zeros(set))
                set &= set - UInt32(1)
            end
        end
    end
    return table
end

function _make_ncr_ranks()
    table = zeros(UInt32, RANKS + 1, RANKS + 1)
    table[1, 1] = 1
    for n in 1:RANKS
        table[n + 1, 1] = 1
        table[n + 1, n + 1] = 1
        for k in 1:(n - 1)
            table[n + 1, k + 1] = table[n, k] + table[n, k + 1]
        end
    end
    return table
end

function _make_rank_index_tables(ncr_ranks::Matrix{UInt32})
    rank_set_to_index = zeros(UInt32, 1 << RANKS)
    index_to_rank_set = zeros(UInt32, RANKS + 1, 1 << RANKS)

    for mask in 0:((1 << RANKS) - 1)
        idx = UInt32(0)
        set = UInt32(mask)
        j = 1
        while set != 0
            bit = trailing_zeros(set)
            idx += ncr_ranks[bit + 1, j + 1]
            set &= set - UInt32(1)
            j += 1
        end

        rank_set_to_index[mask + 1] = idx
        index_to_rank_set[count_ones(mask) + 1, Int(idx) + 1] = UInt32(mask)
    end

    return rank_set_to_index, index_to_rank_set
end

function _make_suit_permutations(nth_unset::Matrix{UInt8})
    permutations = Vector{NTuple{SUITS,UInt8}}(undef, 24)

    for i in 0:23
        idx = i
        used = 0
        suits = ntuple(Val(SUITS)) do j
            suit = idx % (SUITS - j + 1)
            idx ÷= SUITS - j + 1
            shifted_suit = nth_unset[used + 1, suit + 1]
            used |= 1 << shifted_suit
            shifted_suit
        end
        permutations[i + 1] = suits
    end

    return Tuple(permutations)
end

const NTH_UNSET = _make_nth_unset()
const NCR_RANKS = _make_ncr_ranks()
const RANK_SET_TO_INDEX, INDEX_TO_RANK_SET = _make_rank_index_tables(NCR_RANKS)
const SUIT_PERMUTATIONS = _make_suit_permutations(NTH_UNSET)

include("recall.jl")

end
