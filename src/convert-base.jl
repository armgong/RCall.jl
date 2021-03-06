# conversion methods for Base Julia types

# Fallbacks
"""
`rcopy(T,p)` converts a pointer `p` to a Sxp object to a native Julia object of type T.

`rcopy(p)` performs a default conversion.
"""
rcopy{S<:Sxp}(::Type{Any},x::Ptr{S}) = rcopy(x)

# used in vector indexing
for T in [:Cint, :Float64, :Complex128]
    @eval begin
        rcopy(x::$T) = x
        rcopy(::Type{$T}, x::$T) = x
    end
end

rcopy(r::RObject) = rcopy(r.p)
rcopy{T}(::Type{T},r::RObject) = rcopy(T,r.p)


"""
`sexp(S,x)` converts a Julia object `x` to a pointer to a Sxp object of type `S`.

`sexp(x)` performs a default conversion.
"""
# used in vector indexing
sexp(::Type{Cint},x) = convert(Cint,x)
sexp(::Type{Float64},x) = convert(Float64,x)
sexp(::Type{Complex128},x) = convert(Complex128,x)


# NilSxp
sexp(::Void) = sexp(Const.NilValue)
rcopy(::Ptr{NilSxp}) = nothing


# SymSxp
"Create a `SymSxp` from a `Symbol`"
sexp(::Type{SymSxp}, s::AbstractString) = ccall((:Rf_install, libR), Ptr{SymSxp}, (Ptr{UInt8},), s)
sexp(::Type{SymSxp}, s::Symbol) = sexp(SymSxp,string(s))
sexp(s::Symbol) = sexp(SymSxp,s)
rcopy(::Type{Symbol},ss::SymSxp) = Symbol(rcopy(AbstractString,ss))
rcopy(::Type{AbstractString},ss::SymSxp) = rcopy(AbstractString,ss.name)
rcopy{T<:Union{Symbol,AbstractString}}(::Type{T},s::Ptr{SymSxp}) =
    rcopy(T,unsafe_load(s))


# CharSxp
"""
Create a `CharSxp` from a String.
"""
function sexp(::Type{CharSxp}, st::Compat.String)
    if isascii(st)
        ccall((:Rf_mkCharLen, libR), CharSxpPtr, (Ptr{UInt8}, Cint), st, sizeof(st))
    else  # assume UTF-8, is there a way of checking?
        ccall((:Rf_mkCharLenCE, libR), CharSxpPtr,
            (Ptr{UInt8}, Cint, Cint), st, sizeof(st), 1)
    end
end
sexp(::Type{CharSxp}, st::AbstractString) = sexp(CharSxp, string(st))
sexp(::Type{CharSxp}, sym::Symbol) = sexp(CharSxp, string(sym))

rcopy{T<:AbstractString}(::Type{T},s::CharSxpPtr) = convert(T, Compat.String(unsafe_vec(s)))
rcopy(::Type{Symbol},s::CharSxpPtr) = Symbol(rcopy(AbstractString,s))
rcopy(::Type{Int}, s::CharSxpPtr) = parse(Int, rcopy(s))


# general vectors
function sexp{S<:VectorSxp}(::Type{S}, a::AbstractArray)
    ra = protect(allocArray(S, size(a)...))
    try
        for i in 1:length(a)
            ra[i] = a[i]
        end
    finally
        unprotect(1)
    end
    ra
end
sexp(a::AbstractArray) = sexp(VecSxp,a)

function rcopy{T,S<:VectorSxp}(::Type{Array{T}}, s::Ptr{S})
    protect(s)
    v = T[rcopy(T,e) for e in s]
    ret = reshape(v,size(s))
    unprotect(1)
    ret
end
function rcopy{T,S<:VectorSxp}(::Type{Vector{T}}, s::Ptr{S})
    protect(s)
    ret = T[rcopy(T,e) for e in s]
    unprotect(1)
    ret
end

# StrSxp
sexp(::Type{StrSxp}, s::CharSxpPtr) = ccall((:Rf_ScalarString,libR),Ptr{StrSxp},(CharSxpPtr,),s)
"Create a `StrSxp` from an `Symbol`"
sexp(::Type{StrSxp},s::Symbol) = sexp(StrSxp,sexp(CharSxp,s))
"Create a `StrSxp` from an `AbstractString`"
sexp(::Type{StrSxp},st::AbstractString) = sexp(StrSxp,sexp(CharSxp,st))
sexp(st::AbstractString) = sexp(StrSxp,st)
"Create a `StrSxp` from an Abstract String Array"
sexp{S<:AbstractString}(a::AbstractArray{S}) = sexp(StrSxp,a)

rcopy(::Type{Vector}, s::StrSxpPtr) = rcopy(Vector{Compat.String}, s)
rcopy(::Type{Array}, s::StrSxpPtr) = rcopy(Array{Compat.String}, s)
rcopy(::Type{Symbol}, s::StrSxpPtr) = rcopy(Symbol,s[1])
rcopy{T<:AbstractString}(::Type{T},s::StrSxpPtr) = rcopy(T,s[1])


# IntSxp, RealSxp, CplxSxp
for (J,S) in ((:Integer,:IntSxp),
                 (:Real, :RealSxp),
                 (:Complex, :CplxSxp))
    @eval begin
        # Could use Rf_Scalar... methods, but see weird error on Appveyor Windows for Complex.
        function sexp(::Type{$S},v::$J)
            ra = allocArray($S,1)
            unsafe_store!(dataptr(ra),convert(eltype($S),v))
            ra
        end
        function sexp{T<:$J}(::Type{$S}, a::AbstractArray{T})
            ra = allocArray($S, size(a)...)
            copy!(unsafe_vec(ra),a)
            ra
        end
        sexp(v::$J) = sexp($S,v)
        sexp{T<:$J}(a::AbstractArray{T}) = sexp($S,a)

        rcopy{T<:$J}(::Type{T},s::Ptr{$S}) = convert(T,s[1])
        function rcopy{T<:$J}(::Type{Vector{T}},s::Ptr{$S})
            a = Array(T,length(s))
            copy!(a,unsafe_vec(s))
            a
        end
        function rcopy{T<:$J}(::Type{Array{T}},s::Ptr{$S})
            a = Array(T,size(s)...)
            copy!(a,unsafe_vec(s))
            a
        end
        rcopy(::Type{Vector},s::Ptr{$S}) = rcopy(Vector{eltype($S)},s)
        rcopy(::Type{Array},s::Ptr{$S}) = rcopy(Array{eltype($S)},s)
    end
end


# Handle LglSxp seperately
sexp(::Type{LglSxp},v::Union{Bool,Cint}) =
    ccall((:Rf_ScalarLogical,libR),Ptr{LglSxp},(Cint,),v)
function sexp{T<:Union{Bool,Cint}}(::Type{LglSxp}, a::AbstractArray{T})
    ra = allocArray(LglSxp, size(a)...)
    copy!(unsafe_vec(ra),a)
    ra
end
sexp(v::Bool) = sexp(LglSxp,v)
sexp(a::AbstractArray{Bool}) = sexp(LglSxp,a)


rcopy(::Type{Cint},s::Ptr{LglSxp}) = convert(Cint,s[1])
rcopy(::Type{Bool},s::Ptr{LglSxp}) = s[1]!=0

function rcopy(::Type{Vector{Cint}},s::Ptr{LglSxp})
    a = Array(Cint,length(s))
    copy!(a,unsafe_vec(s))
    a
end
function rcopy(::Type{Vector{Bool}},s::Ptr{LglSxp})
    a = Array(Bool,length(s))
    v = unsafe_vec(s)
    for i = 1:length(a)
        a[i] = v[i] != 0
    end
    a
end
function rcopy(::Type{BitVector},s::Ptr{LglSxp})
    a = BitArray(length(s))
    v = unsafe_vec(s)
    for i = 1:length(a)
        a[i] = v[i] != 0
    end
    a
end
function rcopy(::Type{Array{Cint}},s::Ptr{LglSxp})
    a = Array(Cint,size(s)...)
    copy!(a,unsafe_vec(s))
    a
end
function rcopy(::Type{Array{Bool}},s::Ptr{LglSxp})
    a = Array(Bool,size(s)...)
    v = unsafe_vec(s)
    for i = 1:length(a)
        a[i] = v[i] != 0
    end
    a
end
rcopy(::Type{Array},s::Ptr{LglSxp}) = rcopy(Array{Bool},s)
rcopy(::Type{Vector},s::Ptr{LglSxp}) = rcopy(Vector{Bool},s)
function rcopy(::Type{BitArray},s::Ptr{LglSxp})
    a = BitArray(size(s)...)
    v = unsafe_vec(s)
    for i = 1:length(a)
        a[i] = v[i] != 0
    end
    a
end


# Associative types

# R does not have a native dictionary type, but named vectors/lists are often
# used to this effect.
function sexp{S<:VectorSxp}(::Type{S},d::Associative)
    n = length(d)
    vs = protect(allocArray(VecSxp,n))
    ks = protect(allocArray(StrSxp,n))
    try
        for (i,(k,v)) in enumerate(d)
            ks[i] = string(k)
            vs[i] = v
        end

        setnames!(vs,ks)
    finally
        unprotect(2)
    end
    vs
end
sexp{K,V<:AbstractString}(d::Associative{K,V}) = sexp(StrSxp,d)
sexp(d::Associative) = sexp(VecSxp,d)


function rcopy{A<:Associative,S<:VectorSxp}(::Type{A}, s::Ptr{S})
    protect(s)
    local a
    try
        a = A()
        K = keytype(a)
        V = valtype(a)
        for (k,v) in zip(getnames(s),s)
            a[rcopy(K,k)] = rcopy(V,v)
        end
    finally
        unprotect(1)
    end
    a
end

function rcopy{A<:Associative,S<:PairListSxp}(::Type{A}, s::Ptr{S})
    protect(s)
    local a
    try
        a = A()
        K = keytype(a)
        V = valtype(a)
        for (k,v) in s
            a[rcopy(K,k)] = rcopy(V,v)
        end
    finally
        unprotect(1)
    end
    a
end

# Functions
function rcopy{S<:FunctionSxp}(::Type{Function}, s::Ptr{S})
    (args...) -> rcopy(rcall_p(s,args...))
end
function rcopy{S<:FunctionSxp}(::Type{Function}, r::RObject{S})
    (args...) -> rcopy(rcall_p(r,args...))
end
