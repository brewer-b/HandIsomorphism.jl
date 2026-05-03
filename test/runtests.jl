using HandIsomorphism
using Test

recall_spec(recall) = [Int.(collect(round)) for round in recall.cards_per_round_per_round]

@testset "recall constants" begin
    @test recall_spec(IMPERFECT_RECALL) == [[2], [2, 3], [2, 4], [2, 5]]
    @test recall_spec(PERFECT_RECALL) == [[2], [2, 3], [2, 3, 1], [2, 3, 1, 1]]
    @test recall_spec(FLOP_RECALL) == [[2], [2, 3], [2, 3, 1], [2, 3, 2]]
    @test recall_spec(BOARD_RECALL) == [[1], [3], [4], [5]]

    @test [cards_at_round(IMPERFECT_RECALL, round) for round in 1:4] == [2, 5, 6, 7]
    @test [cards_at_round(PERFECT_RECALL, round) for round in 1:4] == [2, 5, 6, 7]
    @test [cards_at_round(FLOP_RECALL, round) for round in 1:4] == [2, 5, 6, 7]
    @test [cards_at_round(BOARD_RECALL, round) for round in 1:4] == [1, 3, 4, 5]
end

@testset "round sizes" begin
    @test round_size(PERFECT_RECALL, 1) == 169
    @test round_size(PERFECT_RECALL, 2) == 1_286_792
    @test round_size(PERFECT_RECALL, 3) == 55_190_538
    @test round_size(PERFECT_RECALL, 4) == 2_428_287_420
end

@testset "card and index conventions" begin
    cards = UInt8[1, 4, 9, 18, 23, 52, 47] # 2c, 2s, 4c, 6d, 7h, As, Ks

    idx = index(PERFECT_RECALL, 4, cards)
    @test index(PERFECT_RECALL, 1, cards) == 1
    for round in 1:4
        round_idx = index(PERFECT_RECALL, round, cards)
        @test 1 <= round_idx <= round_size(PERFECT_RECALL, round)
    end

    out = Vector{UInt8}(undef, cards_at_round(PERFECT_RECALL, 4))
    @test unindex(PERFECT_RECALL, 4, idx, out)
    @test index(PERFECT_RECALL, 4, out) == idx
    @test all(1 .<= out .<= 52)
end

@testset "isomorphism invariance" begin
    cards = UInt8[1, 4, 9, 18, 23, 52, 47]
    pi = (3, 2, 1, 0)

    permuted = map(cards) do card
        zero_based = Int(card) - 1
        rank = zero_based >>> 2
        suit = zero_based & 3
        UInt8(rank * 4 + pi[suit + 1] + 1)
    end
    reordered = UInt8[permuted[2], permuted[1], permuted[5], permuted[3], permuted[4], permuted[6], permuted[7]]

    @test index(PERFECT_RECALL, 4, cards) == index(PERFECT_RECALL, 4, permuted)
    @test index(PERFECT_RECALL, 4, cards) == index(PERFECT_RECALL, 4, reordered)
end

@testset "random round trips" begin
    deck = collect(UInt8(1):UInt8(52))
    out = Vector{UInt8}(undef, cards_at_round(PERFECT_RECALL, 4))
    seed = UInt64(1)

    for _ in 1:10_000
        for i in 1:7
            seed = seed * 0x5851f42d4c957f2d + 0x14057b7ef767814f
            j = i + Int(seed % UInt64(53 - i))
            deck[i], deck[j] = deck[j], deck[i]
        end
        idx = index(PERFECT_RECALL, 4, deck)
        @test 1 <= idx <= round_size(PERFECT_RECALL, 4)
        @test unindex(PERFECT_RECALL, 4, idx, out)
        @test index(PERFECT_RECALL, 4, out) == idx
    end
end

@testset "recall functions do not allocate" begin
    cards = UInt8[1, 4, 9, 18, 23, 52, 47]
    idx = index(PERFECT_RECALL, 4, cards)
    out = Vector{UInt8}(undef, cards_at_round(PERFECT_RECALL, 4))

    round_size(PERFECT_RECALL, 4)
    cards_at_round(PERFECT_RECALL, 4)
    unindex(PERFECT_RECALL, 4, idx, out)

    @test @allocated(index(PERFECT_RECALL, 4, cards)) == 0
    @test @allocated(round_size(PERFECT_RECALL, 4)) == 0
    @test @allocated(cards_at_round(PERFECT_RECALL, 4)) == 0
    @test @allocated(unindex(PERFECT_RECALL, 4, idx, out)) == 0
end
