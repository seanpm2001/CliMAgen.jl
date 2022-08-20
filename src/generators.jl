
using CUDA: CuArray
using Flux
using Functors


"""
    UNetGenerator
"""
struct UNetGenerator
    initial
    downblocks
    resblocks
    upblocks
    final
end

@functor UNetGenerator

function UNetGenerator(
    in_channels::Int,
    num_features::Int=64,
    num_residual::Int=9,
)
    initial_layer = Chain(
        Conv((7, 7), in_channels => num_features; stride=1, pad=3),
        InstanceNorm(num_features),
        x -> relu.(x)
    )

    downsampling_blocks = [
        ConvBlock(3, num_features, num_features * 2, true, true; stride=2, pad=1),
        ConvBlock(3, num_features * 2, num_features * 4, true, true; stride=2, pad=1),
    ]

    resnet_blocks = Chain([ResidualBlock(num_features * 4) for _ in range(1, length=num_residual)]...)

    upsampling_blocks = [
        ConvBlock(3, num_features * 4, num_features * 2, true, false; stride=2, pad=SamePad()),
        ConvBlock(3, num_features * 2, num_features, true, false; stride=2, pad=SamePad()),
    ]

    final_layer = Chain(
        Conv((7, 7), num_features => in_channels; stride=1, pad=3)
    )

    return UNetGenerator(
        initial_layer,
        downsampling_blocks,
        resnet_blocks,
        upsampling_blocks,
        final_layer
    )
end

function (net::UNetGenerator)(x)
    input = net.initial(x)
    for layer in net.downblocks
        input = layer(input)
    end
    input = net.resblocks(input)
    for layer in net.upblocks
        input = layer(input)
    end
    return tanh.(net.final(input))
end


"""
    NoisyUNetGenerator

A UNetGenerator with an even number of resnet layers;
noise is added to the input after half of the resnet layers
operate.
"""
struct NoisyUNetGenerator
    initial
    downblocks
    first_resnet_block
    second_resnet_block
    upblocks
    final
end

@functor NoisyUNetGenerator

function NoisyUNetGenerator(
    in_channels::Int,
    num_features::Int=64,
    num_residual::Int=8,
)
    @assert iseven(num_residual)
    resnet_block_length = div(num_residual, 2)

    initial_layer = Chain(
        Conv((7, 7), in_channels => num_features; stride=1, pad=3),
        InstanceNorm(num_features),
        x -> relu.(x)
    )

    downsampling_blocks = [
        ConvBlock(3, num_features, num_features * 2, true, true; stride=2, pad=1),
        ConvBlock(3, num_features * 2, num_features * 4, true, true; stride=2, pad=1),
    ]

    first_resnet_block = Chain([ResidualBlock(num_features * 4) for _ in range(1, length=resnet_block_length)]...)
    second_resnet_block = Chain([ResidualBlock(num_features * 4) for _ in range(1, length=resnet_block_length)]...)

    upsampling_blocks = [
        ConvBlock(3, num_features * 4, num_features * 2, true, false; stride=2, pad=SamePad()),
        ConvBlock(3, num_features * 2, num_features, true, false; stride=2, pad=SamePad()),
    ]

    final_layer = Chain(
        Conv((7, 7), num_features => in_channels; stride=1, pad=3)
    )

    return NoisyUNetGenerator(
        initial_layer,
        downsampling_blocks,
        first_resnet_block,
        second_resnet_block,
        upsampling_blocks,
        final_layer
    )
end

function (net::NoisyUNetGenerator)(x, r)
    input = net.initial(x)
    for layer in net.downblocks
        input = layer(input)
    end
    input = net.first_resnet_block(input)
    input = input .+ r # add random noise
    input = net.second_resnet_block(input)
    for layer in net.upblocks
        input = layer(input)
    end

    return tanh.(net.final(input))
end

"""
    PatchNet

    A wrapper structure that allows for patch-wise generation of 2D images.
    It uses another network like UNet as input.
    Assumes square inputs.
"""
struct PatchNet
    net
end

@functor PatchNet

function (patch::PatchNet)(x)
    nx, ny, nc, _ = size(x)

    # x and y patch index ranges
    px1 = 1:div(nx, 2)
    px2 = div(nx, 2)+1:nx
    py1 = 1:div(ny, 2)
    py2 = div(ny, 2)+1:ny
    pc1 = 1:nc
    pc2 = nc+1:2nc

    # generate masks for each x_ij patch
    o = view(zero(x) .+ 1, 1:div(nx, 2), 1:div(ny, 2), :, :)
    z = view(zero(x), 1:div(nx, 2), 1:div(ny, 2), :, :)
    m11 = cat(cat(o, z, dims=1), cat(z, z, dims=1), dims=2)
    m12 = cat(cat(z, z, dims=1), cat(o, z, dims=1), dims=2)
    m21 = cat(cat(z, o, dims=1), cat(z, z, dims=1), dims=2)
    m22 = cat(cat(z, z, dims=1), cat(z, o, dims=1), dims=2)

    # generate y_ij recursively
    # y11
    input = cat(cat(z, z, dims=1), cat(z, z, dims=1), dims=2)
    input = cat(input, x .* m11, dims=3)
    y11 = view(patch.net(input), px1, py1, pc2, :)
    # y12
    input = cat(cat(y11, z, dims=1), cat(z, z, dims=1), dims=2)
    input = cat(input, x .* m12, dims=3)
    y12 = view(patch.net(input), px1, py2, pc2, :)
    # y21
    input = cat(cat(y11, z, dims=1), cat(z, z, dims=1), dims=2)
    input = cat(input, x .* m21, dims=3)
    y21 = view(patch.net(input), px2, py1, pc2, :)
    # y22
    input = cat(cat(y11, y21, dims=1), cat(y12, z, dims=1), dims=2)
    input = cat(input, x .* m22, dims=3)
    y22 = view(patch.net(input), px2, py2, pc2, :)

    # assemble full output 
    y = cat(cat(y11, y21, dims=1), cat(y12, y22, dims=1), dims=2)

    return y
end

"""
    RecursiveNet

    A wrapper structure that allows for temporally consistent 2D images.
    It uses another network like UNet as input.
"""
struct RecursiveNet
    net
end

@functor RecursiveNet

function (rec::RecursiveNet)(x)
    _, _, nc, _ = size(x)

    # t1 and t2 index ranges
    p1 = 1:div(nc, 2)
    p2 = (div(nc, 2)+1):nc

    # generate yt1
    pt1 = view(x, :, :, p1, :)
    zer = zero(pt1)
    xt1 = cat(zer, pt1, dims=3)
    yt1 = view(rec.net(xt1), :, :, p2, :)

    # generate yt2
    pt2 = view(x, :, :, p2, :)
    xt2 = cat(yt1, pt2, dims=3)
    yt2 = view(rec.net(xt2), :, :, p2, :)

    # assemble full output
    y = cat(yt1, yt2, dims=3)

    return y
end

"""
    ConvBlock
"""
struct ConvBlock
    conv
end

@functor ConvBlock

function ConvBlock(
    kernel_size::Int,
    in_channels::Int,
    out_channels::Int,
    with_activation::Bool=true,
    down::Bool=true;
    kwargs...
)
    return ConvBlock(
        Chain(
            if down
                Conv((kernel_size, kernel_size), in_channels => out_channels; kwargs...)
            else
                ConvTranspose((kernel_size, kernel_size), in_channels => out_channels; kwargs...)
            end,
            InstanceNorm(out_channels),
            if with_activation
                x -> relu.(x)
            else
                identity
            end)
    )
end

function (net::ConvBlock)(x)
    return net.conv(x)
end


"""
    ResidualBlock
"""
struct ResidualBlock
    block
end

@functor ResidualBlock

function ResidualBlock(
    in_channels::Int
)
    return ResidualBlock(
        Chain(
            ConvBlock(3, in_channels, in_channels, true, true; pad=1),
            ConvBlock(3, in_channels, in_channels, false, true; pad=1)
        )
    )
end

function (net::ResidualBlock)(x)
    return x + net.block(x)
end
