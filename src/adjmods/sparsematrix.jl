################################################# FILE DESCRIPTION #########################################################

# This file contains the SparseMatrixAM adjacency module.

################################################# IMPORT/EXPORT ############################################################
export
SparseMatrixAM, VertexIteratorCSC

type SparseMatrixAM <: AdjacencyModule
   nv::Int
   ne::Int
   fdata::SparseMatrixCSC{Bool, Int}
   bdata::SparseMatrixCSC{Bool, Int}
end


################################################# GENERATORS ###############################################################

function SparseMatrixAM(nv=0)
   fdata = spzeros(Bool, nv, nv)
   bdata = spzeros(Bool, nv, nv)
   SparseMatrixAM(nv, 0, fdata, bdata)
end

function SparseMatrixAM(nv::Int, ne::Int)
   m = sprandbool(nv, nv, ne/(nv*(nv-1)))
   fdata = triu(m,1) | tril(m,-1)
   bdata = fdata'
   SparseMatrixAM(nv, nnz(fdata), fdata, bdata)
end

################################################# ACCESSORS ################################################################

@inline fdata(x::SparseMatrixAM) = x.fdata

@inline bdata(x::SparseMatrixAM) = x.bdata

################################################# INTERNAL IMPLEMENTATION ##################################################

type EdgeIterState
   u::Int
   i0::Int
   done::Bool
end

type EdgeIterCSC <: AbstractVector{EdgeID}
   m::Int
   colptr::Vector{Int}
   rowval::Vector{Int}
end

function EdgeIterCSC(x::SparseMatrixAM)
   EdgeIterCSC(ne(x), x.fdata.colptr, x.fdata.rowval)
end


Base.size(x::EdgeIterCSC) = (x.m,)
Base.length(x::EdgeIterCSC) = x.m
Base.start(x::EdgeIterCSC) = EdgeIterState(1, 1, true)
Base.done(x::EdgeIterCSC, state) = state.done

function Base.next(x::EdgeIterCSC, state)
   colptr = x.colptr
   rowval = x.rowval
   m = x.m

   while(state.i0 > colptr[state.u+1]-1)
      state.u += 1
   end

   e = EdgeID(state.u, rowval[state.i0])
   state.i0 += 1

   if state.i0 > m
      state = start(x)
   else
      state.done = false
   end

   e, state
end

function Base.getindex(x::EdgeIterCSC, i0::Int)
   j = 1

   colptr = x.colptr
   rowval = x.rowval
   m = x.m

   while(j <= m && i0 > colptr[j+1] - 1)
      j += 1
   end

   EdgeID(j, rowval[i0])
end


Base.getindex(x::EdgeIterCSC, ::Colon) = collect(x)

# Todo: Optimize range getindex

function Base.collect(x::EdgeIterCSC) # STUD METHOD :P
   elist = Vector{EdgeID}()
   sizehint!(elist, x.m)

   rowval = x.rowval
   colptr = x.colptr
   m = x.m
   j = 1

   for (i,v) in enumerate(rowval)
      while(j <= m && i > colptr[j+1] - 1)
         j += 1
      end
      push!(elist, EdgeID(j, v))
   end
   elist
end

function Base.show(io::IO, x::EdgeIterCSC)
   write(io, "Edge Iterator with $(x.am.ne) values")
end

################################################# INTERFACE IMPLEMENTATION ##################################################

Base.deepcopy(x::SparseMatrixAM) = SparseMatrixAM(nv(x), ne(x), deepcopy(fdata(x)), deepcopy(bdata(x)))



nv(x::SparseMatrixAM) = x.nv
ne(x::SparseMatrixAM) = x.ne
Base.size(x::SparseMatrixAM) = (x.nv, x.ne)



@inline vertices(x::SparseMatrixAM) = UnitRange{Int}(1, nv(x))
@inline edges(x::SparseMatrixAM) = EdgeIterCSC(x)



@inline hasvertex(x::SparseMatrixAM, v::VertexID) = 1 <= v <= nv(x)

function hasedge(x::SparseMatrixAM, u::VertexID, v::VertexID)
   hasvertex(x, u) && hasvertex(x, v) && fdata(x)[v,u]
end
@inline hasedge(x::SparseMatrixAM, e::EdgeID) = hasedge(x, e...)

function fadj(x::SparseMatrixAM, v::VertexID)
   M = fdata(x)
   slice(M.rowval, nzrange(M, v))
end

function badj(x::SparseMatrixAM, v::VertexID)
   M = bdata(x)
   slice(M.rowval, nzrange(M, v))
end

outdegree(x::SparseMatrixAM, v::VertexID) = length(nzrange(fdata(x), v))
indegree(x::SparseMatrixAM, v::VertexID) = length(nzrange(bdata(x), v))



function addvertex!(x::SparseMatrixAM, numv::Int = 1)
   x.fdata = grow(fdata(x), numv)
   x.bdata = grow(bdata(x), numv)
   x.nv += numv
   nothing
end

function rmvertex!(x::SparseMatrixAM, vs)
   x.fdata = remove_cols(fdata(x), vs)
   x.bdata = remove_cols(bdata(x), vs)
   x.nv -= length(vs)
   x.ne = nnz(fdata(x))
   nothing
end

function addedge!(x::SparseMatrixAM, u::Int, v::Int)
   fdata(x)[v,u] = true
   bdata(x)[u,v] = true
   x.ne += 1
   nothing
end
@inline addedge!(x::SparseMatrixAM, e::EdgeID) = addedge!(x, e...)

function addedge!(x::SparseMatrixAM, elist::AbstractVector{EdgeID})
   for e in elist
      addedge!(x, e)
   end
end

function rmedge!(x::SparseMatrixAM, u::Int, v::Int)
   x.ne -= 1
   fdata(x)[v,u] = false
   bdata(x)[u,v] = false
   nothing
end
rmedge!(x::SparseMatrixAM, e::EdgeID) = rmedge!(x, e...)

function rmedge!(x::SparseMatrixAM, elist::AbstractVector{EdgeID})
   fd = fdata(x)
   bd = bdata(x)
   for e in elist
      x.ne -= 1
      fd[e...] = false
      bd[e...] = false
   end
   nothing
end

################################################# SUBGRAPH #####################################################################

function subgraph(x::SparseMatrixAM, vlist::AbstractVector{VertexID})
   vlen = length(vlist)
   M = fdata(x)[vlist,vlist]
   SparseMatrixAM(length(vlist), nnz(M), M, M')
end

function subgraph(x::SparseMatrixAM, elist::AbstractVector{EdgeID})
   M = init_spmx(nv(x), elist, fill(true, length(elist)))
   SparseMatrixAM(nv(x), nnz(M), M, M')
end