module HandIsomorphism

export HandIndexers, indexer_size, indexer_index, indexer_unindex

using StaticArrays

# Set the path to your shared library
const libpath = "lib/libhand-isomorphism"

mutable struct HandIndexers
    ptr::Ptr{Cvoid}
    function HandIndexers(cards_per_round::Vector{Vector{T}}) where {T<:Integer}
        cards_per_round_uint8::Vector{Vector{UInt8}} = [Vector{UInt8}(round) for round in cards_per_round]
        sizes::Vector{Csize_t} = [length(round) for round in cards_per_round]
        num_rounds::Csize_t = length(cards_per_round)

        ptr = ccall((:HandIsomorphism_create, libpath), Ptr{Cvoid}, (Ptr{Ptr{UInt8}}, Ptr{Csize_t}, Csize_t), cards_per_round_uint8, sizes, num_rounds)
        obj = new(ptr)
        finalizer(obj) do x
            ccall((:HandIsomorphism_destroy, libpath), Cvoid, (Ptr{Cvoid},), x.ptr)
        end
        return obj
    end
end

function indexer_size(hi::HandIndexers, round::Integer)::UInt64
    ccall((:HandIsomorphism_size, libpath), UInt64, (Ptr{Cvoid}, Cint), hi.ptr, round - 1)
end

function indexer_index(hi::HandIndexers, round::Integer, cards::Vector{<:Integer})::UInt64
    cards_uint8 = zeros(MVector{11, UInt8})
    @inbounds for i in 1:length(cards)
        cards_uint8[i] = UInt8(cards[i] - 1)
    end
    index = 1 + ccall((:HandIsomorphism_index, libpath), UInt64, (Ptr{Cvoid}, Cint, Ptr{UInt8}), hi.ptr, round - 1, cards_uint8)
    return index
end

function indexer_unindex(hi::HandIndexers, round, index, output::Vector{UInt8})
    status = ccall((:HandIsomorphism_unindex, libpath), Bool, (Ptr{Cvoid}, Cint, UInt64, Ptr{UInt8}),
          hi.ptr, round - 1, index - 1, output)
    @assert status
    output .+= 1
end

end
