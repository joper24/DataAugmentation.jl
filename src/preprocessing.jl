# ### [`ToEltype`](#)

"""
    ToEltype(T)

Converts any `AbstractArrayItem` to an `AbstractArrayItem{N, T}`.

Supports `apply!`.

## Examples

{cell=ToEltype}
```julia
using DataAugmentation

tfm = ToEltype(Float32)
item = ArrayItem(rand(Int, 10))
apply(tfm, item)
```
"""
struct ToEltype{T} <: Transform end
ToEltype(T::Type) = ToEltype{T}()

apply(::ToEltype{T}, item::AbstractArrayItem{N, <:T}; randstate = nothing) where {N, T} = item
function apply(::ToEltype{T1}, item::AbstractArrayItem{N, T2}; randstate = nothing) where {N, T1, T2}
    newdata = map(x -> convert(T1, x), itemdata(item))
    item = setdata(item, newdata)
    return item
end

function apply!(buf, ::ToEltype, item::AbstractArrayItem; randstate = nothing)
    ## copy! does type conversion under the hood
    copy!(itemdata(buf), itemdata(item))
    return buf
end

# ### [`Normalize`](#)

"""
    Normalize(means, stds)

Normalizes the last dimension of an `AbstractArrayItem{N}`.

Supports `apply!`.

## Examples

Preprocessing a 3D image with 3 color channels.

{cell=Normalize}
```julia
using DataAugmentation, Images
image = Image(rand(RGB, 20, 20, 20))
tfms = ImageToTensor() |> Normalize((0.1, -0.2, -0.1), (1,1,1.))
apply(tfms, image)
```

"""
# MARK - Normalize Struct Explained
#* Creates the trait type "Normalize" that extends the abstract style "Transform"
### Transform
#* Abstract type defined in base.jl
### Normalize{N} 
#* Normalize - name of the struct ... It is of the abstract type Transform
    #* So Normalize is a subtype of Transform
    #* N - The dimensionality of the struct 
### means & stds
#* static arrays of size N
    #* "Note that here "statically sized" means that the size can be determined from the type, and "static" does not necessarily imply immutable." - https://github.com/JuliaArrays/StaticArrays.jl
struct Normalize{N} <: Transform
    means::SVector{N}
    stds::SVector{N}
end

### Outer contructor for the Normalize Struct
#* N = length(means) - The dimensionality of the Normalize Struct 
function Normalize(means, stds)
    length(means) == length(stds) || error("`means` and `stds` must have same length")
    N = length(means) 
    return Normalize{N}(SVector{N}(means), SVector{N}(stds))
end

function apply(tfm::Normalize, item::ArrayItem{N, T}; randstate = nothing) where {N, T}
    means = reshape(convert.(T, tfm.means), (1 for _ = 2:N)..., N)
    stds = reshape(convert.(T, tfm.stds), (1 for _ = 2:N)..., N)
    return ArrayItem(normalize(itemdata(item), means, stds))
end

function apply!(buf, tfm::Normalize, item::ArrayItem; randstate = nothing)
    copy!(itemdata(buf), itemdata(item))
    means = reshape(convert.(T, tfm.means), (1 for _ = 2:N)..., N)
    stds = reshape(convert.(T, tfm.stds), (1 for _ = 2:N)..., N)
    normalize!(itemdata(buf), means, stds)
    return buf
end

function normalize!(a, means, stds)
    a .-= means
    a ./= stds
    return a
end


normalize(a, means, stds) = normalize!(copy(a), means, stds)

function Normalize(array)
    slices = ones(Bool, size(array))
    means = mean(array[slices])
    stds = std(array[slices])
    
    ### mormalize! function does below code so just call that instead
    # array[slices] = (array[slices] .- means) / stds
    array = normalize!(array, means, stds)
    
    return array
end

function denormalize!(a, means, stds)
    a .*= stds
    a .+= means
    return a
end

denormalize(a, means, stds) = denormalize!(copy(a), means, stds)


# ### [`ImageToTensor`]

"""
    ImageToTensor()

Expands an `Image{N, T}` of size `sz` to an `ArrayItem{N+1}` with
size `(sz..., ch)` where `ch` is the number of color channels of `T`.

Supports `apply!`.

## Examples

{cell=ImageToTensor}
```julia
image = Image(rand(RGB, 50, 50))
tfm = ImageToTensor()
apply(tfm, image)
```

"""
struct ImageToTensor{T} <: Transform end

ImageToTensor(T::Type{<:Number} = Float32) = ImageToTensor{T}()


function apply(::ImageToTensor{T}, image::Image; randstate = nothing) where T
    return ArrayItem(imagetotensor(itemdata(image), T))
end


function apply!(buf::I, ::ImageToTensor, image::I; randstate = nothing) where {N, I<:Image{N}}
    imagetotensor!(buf.data, image.data)
    return buf
end

function imagetotensor(image::AbstractArray{C, N}, T = Float32) where {C<:Color, N}
    T.(permuteddimsview(channelview(image), ((i for i in 2:N+1)..., 1)))
end

function imagetotensor(image::AbstractArray{C, N}, T = Float32) where {TC, C<:Color{TC, 1}, N}
    return T.(channelview(image))
end


function imagetotensor!(buf, image::AbstractArray{<:AbstractRGB, N}) where N
    permutedims!(
        buf,
        channelview(image),
        (2, 3, 1))
end
tensortoimage(a::AbstractArray{T, 3}) where T = colorview(RGB, permuteddimsview(a, (3, 1, 2)))
tensortoimage(a::AbstractArray{T, 2}) where T = colorview(Gray, a)

function onehot(T, x::Int, n::Int)
    v = fill(zero(T), n)
    v[x] = one(T)
    return v
end
onehot(x, n) = onehot(Float32, x, n)
