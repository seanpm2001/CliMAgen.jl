using BSON
using CUDA
using Flux
using Images
using ProgressMeter
using Plots
using Random
using Statistics
using TOML

using CliMAgen
package_dir = pkgdir(CliMAgen)
include(joinpath(package_dir,"examples/utils_data.jl"))
include(joinpath(package_dir,"examples/utils_analysis.jl"))

function run_analysis(params; FT=Float32, logger=nothing)
    # unpack params
    savedir = params.experiment.savedir
    rngseed = params.experiment.rngseed
    nogpu = params.experiment.nogpu

    batchsize = params.data.batchsize
    resolution = params.data.resolution
    npairs_per_τ = params.data.npairs_per_tau
    fraction = params.data.fraction
    standard_scaling = params.data.standard_scaling
    preprocess_params_file = joinpath(savedir, "preprocessing_standard_scaling_$standard_scaling.jld2")

    noised_channels = params.model.noised_channels
    context_channels = params.model.context_channels
    nsamples = params.sampling.nsamples
    nimages = params.sampling.nimages
    nsteps = params.sampling.nsteps
    sampler = params.sampling.sampler
    tilesize_sampling = params.sampling.tilesize

    # set up rng
    rngseed > 0 && Random.seed!(rngseed)

    # set up device
    if !nogpu && CUDA.has_cuda()
        device = Flux.gpu
        @info "Sampling on GPU"
    else
        device = Flux.cpu
        @info "Sampling on CPU"
    end

    # set up dataset
    dl, dl_test = get_data_correlated_ou2d(
        batchsize;
        pairs_per_τ = :all,
        f = 0.1,
        resolution=resolution,
        FT=Float32,
        standard_scaling = standard_scaling,
        read = true,
        save = false,
        preprocess_params_file,
        rng=Random.GLOBAL_RNG
    )

    test = cat([x for x in dl_test]..., dims=4)
    xtest = test[:,:,1:noised_channels,1:nsamples]
    ctest = test[:,:,(noised_channels+1):(noised_channels+context_channels),1:nsamples]

    # To use Images.Gray, we need the input to be between 0 and 1.
    # Obtain max and min here using the whole data set
    #maxtest = maximum(xtest, dims=(1, 2, 4))
    #mintest = minimum(xtest, dims=(1, 2, 4))

    # set up model
    checkpoint_path = joinpath(savedir, "checkpoint.bson")
    BSON.@load checkpoint_path model model_smooth opt opt_smooth
    model = device(model)
    
    # sample from the tested model
    time_steps, Δt, init_x = setup_sampler(
        model,
        device,
        tilesize_sampling,
        noised_channels;
        num_images=nsamples,
        num_steps=nsteps,
    )
    samples = CliMAgen.Euler_Maruyama_timeseries_sampler(model, init_x, time_steps, Δt; c=ctest[:,:,:,[1]])
    

    dt_save = 1.0
    ac, lag, npairs = autocorr(samples, 1, 16, 16)
    ac_l = autocorr_inverse_cdf.(0.05, npairs, ac)
    ac_up = autocorr_inverse_cdf.(0.95, npairs, ac)
    Plots.plot(lag*dt_save, ac,  ribbon = (ac .- ac_l, ac_up .- ac), label = "Generated", ylabel = "Autocorrelation Coeff", xlabel = "Lag (time)", margin = 10Plots.mm)

    ac_truth, lag, npairs = autocorr(xtest, 1, 16, 16) # this is a portion of the timeseries if stride = 1
    ac_truth_l = autocorr_inverse_cdf.(0.05, npairs, ac_truth)
    ac_truth_up = autocorr_inverse_cdf.(0.95, npairs, ac_truth)
    Plots.plot!(lag*dt_save, ac_truth, ribbon = (ac_truth .- ac_truth_l, ac_truth_up .- ac_truth), label = "Training")
    Plots.savefig(joinpath(savedir,"autocorr_samples.png"))

    # create plot showing distribution of spatial mean of generated and real images
    spatial_mean_plot(xtest[:, :, :, 1:k], samples, savedir, "spatial_mean_distribution.png", logger=logger)

    # create q-q plot for cumulants of pre-specified scalar statistics
    qq_plot(xtest[:, :, :, 1:k], samples, savedir, "qq_plot.png", logger=logger)

    # create plots for comparison of real vs. generated spectra
    spectrum_plot(xtest[:, :, :, 1:k], samples, savedir, "mean_spectra.png", logger=logger)
    clims = extrema(xtest)
    frames =nsamples
    animation = @animate for i = 1:frames
        heatmap(samples[:,:,1,i],
                xaxis = false, yaxis = false, xticks = false, yticks = false,clims = clims,colorbar = :none
                )
    end
    gif(animation, joinpath(savedir,"timeseries.gif"),fps=10)

    animation = @animate for i = 1:frames
        heatmap(samples[:,:,1,i],
                xaxis = false, yaxis = false, xticks = false, yticks = false,colorbar = :none
                )
    end
    gif(animation, joinpath(savedir,"timeseries_no_clims.gif"),fps=10)

    # get pure gen samples
    gen_images = Euler_Maruyama_sampler(model, init_x, time_steps, Δt; c=ctest[:,:,:,1:nsamples])
    # create plot showing distribution of spatial mean of generated and real images
    spatial_mean_plot(xtest[:, :, :, 1:k], gen_images, savedir, "spatial_mean_distribution_images.png", logger=logger)

    # create q-q plot for cumulants of pre-specified scalar statistics
    qq_plot(xtest[:, :, :, 1:k], gen_images, savedir, "qq_plot_images.png", logger=logger)

    # create plots for comparison of real vs. generated spectra
    spectrum_plot(xtest[:, :, :, 1:k], gen_images, savedir, "mean_spectra_images.png", logger=logger)
    loss_plot(savedir, "losses.png"; xlog = false, ylog = true)    
end

function main(; experiment_toml="Experiment_all_data_context.toml")
    FT = Float32

    # read experiment parameters from file
    params = TOML.parsefile(experiment_toml)
    params = CliMAgen.dict2nt(params)

    run_analysis(params; FT=FT)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(experiment_toml=ARGS[1])
end
