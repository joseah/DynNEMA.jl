function fast_neighbors(data, n_neighbors; metric=Euclidean(), seed = 66)
    """
    Calculates the nearest neighboring points for each point in `data`
    
    Parameters
    ----------
    data : a coordinate matrix of shape <num coords> x <num dimensions>
    n_neighbors : the number of nearest neighbors
    metric : distance metric for calculating neighbor distances.
             See `Distances`` package for metric options.
    
    Returns
    ------
    matrix of shape <num coords> x <n_neighbors>,
      with row i containing the neighbors of data[i]
    """
    
    Random.seed!(seed)

    graph = nndescent(transpose(data), n_neighbors - 1, metric)
    indices, _ = knn_matrices(graph)

    indices = vcat(transpose(1:size(indices, 2)), indices)
    indices = [row for row in eachcol(indices)]
    
    return indices

end


function graph_poisson_disk(rng, neighbors, n_pseudocells, n_candidates=100)
    """
    Calculates Poisson disk samples on a graph specified by `neighbors`
    
    Parameters
    ----------
    rng : Random number generator
    neighbors : a 2D list specifying the neighbors of each node in the graph,
                neighbors[i] is a list of the neighbors of node i
    n_pseudocells : the number of Poisson disk samples to generate
    n_candidates : the number of candidates to choose between when drawing a new sample,
                   by default is 100    
    Returns
    ------
    a vector with each element being a sublist containing the nodes in a Poisson disk sample
    """
    
    # Select cell at random
    sample = rand(rng, 1:length(neighbors))  # randomly choose a node
    samples = [sample]
    
    # Remove it from the available samples
    available_samples = setdiff(1:length(neighbors), sample)  # indices except `sample`
    
    # Get neighbors of cell `sample`
    included_samples = neighbors[sample]  # neighbors of the sample node
    
    # Create sets for all neighbors
    neighbor_sets = [Set(i) for i in neighbors]
    
    while length(samples) < n_pseudocells && length(available_samples) > 0
        # Choose `n_candidates` out of the available cells (indices)
        sample_candidates = rand(rng, available_samples, n_candidates)  # select candidate nodes
        sample_candidates = unique(sample_candidates)  # get unique candidates
        
        # Add to whole list of candidates
        sample_candidates_all = sample_candidates
        
        # For each cell in `sample_candidates`, check if any of their neighbors are in the `included_samples` set
        sample_candidates = filter(i -> isempty(Set(neighbor_sets[i]) ∩ included_samples), sample_candidates)
        
        # If no candidates, reset to all sample candidates
        if length(sample_candidates) == 0
            sample_candidates = sample_candidates_all
        end
        
        # Retrieve neighbors for all `sample_candidates`
        super_neighbors = []
        for i in sample_candidates
            push!(super_neighbors, neighbors[i])
        end
        
        # Get intersection of neighbors between `included_samples` and all `sample_candidates` neighbors
        sample_density = [length(intersect(Set(i), included_samples)) / length(i) for i in super_neighbors]
        
        # Select the candidate with the minimum density
        new_sample = sample_candidates[argmin(sample_density)]
        
        # Add the cell with the lowest overlap density to the `samples` list
        push!(samples, new_sample)
        
        # Update the available samples by removing the neighbors of `new_sample`
        available_samples = setdiff(available_samples, neighbors[new_sample])
        
        # Update `included_samples` with the neighbors of the new sample
        included_samples = Set(included_samples) ∪ Set(neighbors[new_sample])
        

    end
    

    return samples

end

function calculate_poisson_disks(rng::AbstractRNG, embeddings::DataFrame, donor_ids::AbstractVector, n_disks::Int, verbose::Bool = true)

    sample_fraction = round(n_disks / nrow(embeddings))
    ks = Int.([round(nrow(embeddings) / n_disks)])
    donor_id_set = unique(donor_ids)

    random_neighbors = []
    poisson_neighbors = []

    pd = Vector{DataFrame}(undef, length(donor_id_set))

    for donor_id in donor_id_set

        i = findfirst(isequal(donor_id), donor_id_set)

        donor_idxs = [j for j in 1:nrow(embeddings) if donor_ids[j] == donor_id]

        printlnv("----------------", verbose = verbose)
        printlnv("Donor: ", donor_id, " [$i / $(length(donor_id_set))]", verbose = verbose)
        printlnv("N. Cells: ", length(donor_idxs), verbose = verbose)
        

        n_samples = max(15, Int(round(length(donor_idxs) * n_disks / nrow(embeddings))))
        n_neighbors = first(ks)
        printlnv("N. Disks: ", n_samples, "   N. Neighbors: ", n_neighbors, verbose = verbose)

        if length(donor_idxs) >= n_neighbors

            neighbors = Dynema.fast_neighbors(Matrix(embeddings[donor_idxs, :]), n_neighbors)
            
            random_samples = rand(rng, 1:length(donor_idxs), n_samples)
            poisson_samples = Dynema.graph_poisson_disk(rng, neighbors, n_samples)

            printlnv("Random Coverage:", coverage(random_samples, neighbors), verbose = verbose)  
            printlnv("Poisson Coverage:", coverage(poisson_samples, neighbors), verbose = verbose)

            random_neighbor = [donor_idxs[j] for j in neighbors[random_samples]]
            poisson_neighbor = [donor_idxs[j] for j in neighbors[poisson_samples]]


            # ----------------------------- Random neighbors ----------------------------- #

            idx2neighborhood = Dict{Int, Array{Int}}()
            for n in 1:length(random_neighbor)
                for m in random_neighbor[n]
                    if !haskey(idx2neighborhood, m)
                        idx2neighborhood[m] = [n]
                    else
                        push!(idx2neighborhood[m], n)
                    end
                end
            end

            idx2neighborhood = Dict(i => rand(rng, idx2neighborhood[i], 1) for i in keys(idx2neighborhood))
            

            neighborhood2idx = Dict{Int, Array{Int}}()
            for k in keys(idx2neighborhood)
                if !haskey(neighborhood2idx, first(idx2neighborhood[k]))
                    neighborhood2idx[first(idx2neighborhood[k])] = [k]
                else
                    push!(neighborhood2idx[first(idx2neighborhood[k])], k)
                end
            end

            random_neighbor = [neighborhood2idx[i] for i in keys(neighborhood2idx)]

            # ----------------------------- Poisson neighbors ---------------------------- #

            idx2neighborhood = Dict{Int, Array{Int}}()

            for n in 1:length(poisson_neighbor)
                for m in poisson_neighbor[n]
                    if !haskey(idx2neighborhood, m)
                        idx2neighborhood[m] = [n]
                    else
                        push!(idx2neighborhood[m], n)
                    end
                end
            end

            idx2neighborhood = Dict(i => rand(rng, idx2neighborhood[i], 1) for i in keys(idx2neighborhood))

            
            neighborhood2idx = Dict{Int, Vector{Union{Int, Missing}}}()
            for k in keys(idx2neighborhood)
                if !haskey(neighborhood2idx, first(idx2neighborhood[k]))
                    neighborhood2idx[first(idx2neighborhood[k])] = [k]
                else
                    push!(neighborhood2idx[first(idx2neighborhood[k])], k)
                end
            end
            poisson_neighbor = [neighborhood2idx[i] for i in keys(neighborhood2idx)]

            [append!(v, fill(missing, n_neighbors - length(v))) for v in poisson_neighbor]
            
            poisson_neighbor = DataFrame(poisson_neighbor, :auto)
            poisson_neighbor = permutedims(poisson_neighbor)
            rename!(poisson_neighbor, "cell" .* "_".* string.(1:n_neighbors))

            
            insertcols!(poisson_neighbor, 1, "donor_id" => fill(donor_id, nrow(poisson_neighbor)))

            poisson_disks_labels = poisson_neighbor.donor_id .*  "-" .* string.(1:nrow(poisson_neighbor))
            insertcols!(poisson_neighbor, 2, "disk_id" => poisson_disks_labels)

            pd[i] = poisson_neighbor
            
        else
            @warn "Skipping donor $donor_id. Number of neighbors is greater than number of cells.
            Please adjust the number of disks"
        end
        printlnv("----------------", verbose = verbose)

    end


    return(reduce(vcat, pd))

end


function coverage(samples, neighbors)
    """
    Calculates the coverage of the samples over the neighbors.

    # Arguments
    - samples: A vector of sample indices.
    - neighbors: A vector of neighbor indices.

    # Returns
    - The coverage of the samples over the neighbors.
    """
    included = unique(reduce(vcat, neighbors[samples]))
    return length(included) / length(neighbors)
end