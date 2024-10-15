include("sampler.jl")
using CairoMakie

nsamples = 100
nsteps = 250 
resolution = (192, 96)
time_steps, Δt, init_x = setup_sampler(
    score_model_smooth,
    device,
    resolution,
    inchannels;
    num_images=nsamples,
    num_steps=nsteps,
)


ntotal = 1000
total_samples = zeros(resolution..., inchannels, ntotal)
cprelim = zeros(resolution..., context_channels, nsamples)
rng = MersenneTwister(1234)
tot = ntotal ÷ nsamples
for i in ProgressBar(1:tot)
    if i ≤ (tot ÷ 2)
        # cprelim = reshape(gfp(Float32(0.1)), (192, 96, 1, 1)) * gfp_scale
        cprelim .= contextfield[:, :, :, 1:1] # ensemble_mean[:, :, :, 1:1]
    else
        # cprelim = reshape(gfp(Float32(1.0)), (192, 96, 1, 1)) * gfp_scale
        cprelim .= contextfield[:, :, :, end:end]# ensemble_mean[:, :, :, end:end]
    end
    c = device(cprelim)
    samples = Array(Euler_Maruyama_sampler(score_model_smooth, init_x, time_steps, Δt; rng, c))
    total_samples[:, :, :, (i-1)*nsamples+1:i*nsamples] .= samples
end

colorrange = extrema(field)
fig = Figure()
ax = Axis(fig[1, 1]; title = "ai")
heatmap!(ax, Array(total_samples[:,:,1,1]); colorrange, colormap = :balance)
ax = Axis(fig[1, 2]; title = "ai")
hist!(ax, Array(total_samples[:,:,1,1:ntotal÷2])[:], bins = 100)
xlims!(ax, colorrange)
ax = Axis(fig[2, 1]; title = "data")
heatmap!(ax, Array(total_samples[:,:,1,end]); colorrange, colormap = :balance)
ax = Axis(fig[2, 2]; title = "data")
hist!(ax, Array(total_samples[:,:,1,ntotal÷2+1:end])[:], bins = 100)
xlims!(ax, colorrange)
save("samples_pr_temp.png", fig)

index_1 = [59, 90]
index_2 = [130, 46]
index_3 = [140, 47]
total_samples_physical = (total_samples .* physical_sigma) .+ physical_mu
rfield = (reshape(oldfield, 192, 96, 2, 251, 45) .* physical_sigma) .+ physical_mu

fig  = Figure(resolution = (1200, 800))
binsize = 30
ax = Axis(fig[1, 1]; title = "ai ($index_1)")
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
ax = Axis(fig[1, 2]; title = "ai ($index_2)")
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
ax = Axis(fig[1, 3]; title = "ai ($index_3)")
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)

ax = Axis(fig[2, 1]; title = "ai ($index_1)")
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],2,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],2,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
ax = Axis(fig[2, 2]; title = "ai ($index_2)")
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],2,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],2,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
ax = Axis(fig[2, 3]; title = "ai ($index_3)")
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],2,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],2,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)

save("samples_pr_temp.png", fig)

##
fig  = Figure(resolution = (1200, 800))
binsize = 30
ax = Axis(fig[1, 1]; title = "ai ($index_1)")
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 295, 310)
ax = Axis(fig[1, 2]; title = "ai ($index_2)")
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 296, 303)
ax = Axis(fig[1, 3]; title = "ai ($index_3)")
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],1,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],1,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax,  260, 280)

n = 2
ax = Axis(fig[2, 1]; title = "data ($index_1)")
hist!(ax, Array(rfield[index_1[1],index_1[2],1, 35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_1[1],index_1[2],1, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 295, 310)
ax = Axis(fig[2, 2]; title = "data ($index_2)")
hist!(ax, Array(rfield[index_2[1],index_2[2],1, 35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_2[1],index_2[2],1, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax,  296, 303)
ax = Axis(fig[2, 3]; title = "data ($index_3)")
hist!(ax, Array(rfield[index_3[1],index_3[2],1,35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_3[1],index_3[2],1, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 260, 280)
save("samples_hist_pr_temp.png", fig)
##

fig  = Figure(resolution = (1200, 800))
binsize = 30
state = 2
ax = Axis(fig[1, 1]; title = "ai ($index_1)")
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],state,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_1[1],index_1[2],state,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 295, 310)
ax = Axis(fig[1, 2]; title = "ai ($index_2)")
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],state,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_2[1],index_2[2],state,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 296, 303)
ax = Axis(fig[1, 3]; title = "ai ($index_3)")
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],state,1:ntotal÷2])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(total_samples_physical[index_3[1],index_3[2],state,(ntotal÷2+1):end])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax,  260, 280)

n = 2
ax = Axis(fig[2, 1]; title = "data ($index_1)")
hist!(ax, Array(rfield[index_1[1],index_1[2],state, 35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_1[1],index_1[2],state, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 295, 310)
ax = Axis(fig[2, 2]; title = "data ($index_2)")
hist!(ax, Array(rfield[index_2[1],index_2[2],state, 35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_2[1],index_2[2],state, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax,  296, 303)
ax = Axis(fig[2, 3]; title = "data ($index_3)")
hist!(ax, Array(rfield[index_3[1],index_3[2],state,35-n:35+n, :])[:], bins = binsize, color = (:blue, 0.5), normalization = :pdf)
hist!(ax, Array(rfield[index_3[1],index_3[2],state, end-5:end, :])[:], bins = binsize, color = (:orange, 0.5), normalization = :pdf)
# xlims!(ax, 260, 280)
save("samples_hist_pr_temp_2.png", fig)

fig = Figure() 
ax = Axis(fig[1, 1]; title = "losses")
lines!(ax, [loss[1] for loss in losses], label = "train")
lines!(ax, [loss[1] for loss in losses_test], label = "test")
save("losses_pr_temp.png", fig)


#=
for i in 1:10
    fig = Figure()
    i1 = rand(1:192)# 150
    j1 = rand(1:96)# 48
    i2 = rand(1:192)# 48
    j2 = rand(1:96) # 48
    ax = Axis(fig[1, 1]; title = "ai ($i1,$j1)")
    hist!(ax, Array(total_samples[i1,j1,1,:])[:], bins = 20)
    ax = Axis(fig[1, 2]; title = "ai ($i2,$j2)")
    hist!(ax, Array(total_samples[i2,j2,1,:])[:], bins = 20)
    ax = Axis(fig[2, 1]; title = "data ($i1,$j1)")
    hist!(ax, Array(field[i1,j1,1,:])[:], bins = 20)
    ax = Axis(fig[2, 2]; title = "data ($i2,$j2)")
    hist!(ax, Array(field[i2,j2,1,:])[:], bins = 20)
    save("samples_hist_temp_$i.png", fig)
end
=#