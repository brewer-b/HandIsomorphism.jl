using HandIsomorphism
using Test

const HI = HandIsomorphism

@testset "round sizes" begin
    preflop = HI.Indexer((2,))
    flop = HI.Indexer((2, 3))
    turn = HI.Indexer((2, 3, 1))
    river = HI.Indexer((2, 3, 1, 1))

    @test round_size(preflop, 1) == 169
    @test round_size(flop, 1) == 169
    @test round_size(turn, 1) == 169
    @test round_size(river, 1) == 169
    @test round_size(flop, 2) == 1_286_792
    @test round_size(turn, 2) == 1_286_792
    @test round_size(river, 2) == 1_286_792
    @test round_size(turn, 3) == 55_190_538
    @test round_size(river, 3) == 55_190_538
    @test round_size(river, 4) == 2_428_287_420
end

@testset "card and index conventions" begin
    river = HI.Indexer((2, 3, 1, 1))
    cards = UInt8[1, 4, 9, 18, 23, 52, 47] # 2c, 2s, 4c, 6d, 7h, As, Ks
    indices = Vector{UInt64}(undef, 4)

    idx = index(river, cards, indices)
    @test idx == index(river, cards)
    @test indices[1] == 1
    for round in 1:4
        @test 1 <= indices[round] <= round_size(river, round)
    end

    out = Vector{UInt8}(undef, 7)
    @test unindex_all(river, 4, idx, out)
    @test index(river, out) == idx
    @test all(1 .<= out .<= 52)
end

@testset "isomorphism invariance" begin
    river = HI.Indexer((2, 3, 1, 1))
    cards = UInt8[1, 4, 9, 18, 23, 52, 47]
    pi = (3, 2, 1, 0)

    permuted = map(cards) do card
        zero_based = Int(card) - 1
        rank = zero_based >>> 2
        suit = zero_based & 3
        UInt8(rank * 4 + pi[suit + 1] + 1)
    end
    reordered = UInt8[permuted[2], permuted[1], permuted[5], permuted[3], permuted[4], permuted[6], permuted[7]]

    @test index(river, cards) == index(river, permuted)
    @test index(river, cards) == index(river, reordered)
end

@testset "random round trips" begin
    river = HI.Indexer((2, 3, 1, 1))
    deck = collect(UInt8(1):UInt8(52))
    out = Vector{UInt8}(undef, 7)
    seed = UInt64(1)

    for _ in 1:10_000
        for i in 1:7
            seed = seed * 0x5851f42d4c957f2d + 0x14057b7ef767814f
            j = i + Int(seed % UInt64(53 - i))
            deck[i], deck[j] = deck[j], deck[i]
        end
        idx = index(river, deck)
        @test 1 <= idx <= round_size(river, 4)
        @test unindex_all(river, 4, idx, out)
        @test index(river, out) == idx
    end
end

@testset "exported functions do not allocate" begin
    river = HI.Indexer((2, 3, 1, 1))
    cards = UInt8[1, 4, 9, 18, 23, 52, 47]
    indices = Vector{UInt64}(undef, 4)
    out = Vector{UInt8}(undef, 7)

    idx = index(river, cards, indices)
    unindex_all(river, 4, idx, out)

    @test @allocated(round_size(river, 4)) == 0
    @test @allocated(index(river, cards)) == 0
    @test @allocated(index(river, cards, indices)) == 0
    @test @allocated(unindex_all(river, 4, idx, out)) == 0
end
