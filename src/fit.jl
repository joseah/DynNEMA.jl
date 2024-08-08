
function fit_model(form, resample)

    mdl = LinearMixedModel(form, resample)
    mdl.optsum.ftol_rel = 1e-8
    boot_model = fit!(mdl)
    DataFrame([boot_model.βs])

end



function boot_model(rng, md, form, n)

    res_boot = map(1:n) do i 
    index = sample_index(rng, nrow(md))
        fit_model(form, md[index, :])
    end

    return res_boot

end