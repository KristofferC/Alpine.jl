"""
    Set up a basic lifted mip model without any additional information
    Certain parts model is intended to be deep-copied at each iteration to create a new MIP model.
    Each non-linear term in the original model is lifted with a variable.
"""
function create_bounding_mip(m::PODNonlinearModel; kwargs...)

    m.model_mip = Model(solver=m.mip_solver) # Construct jump model

    start_build = time()
    # ------- Algorithm ------ #
    amp_post_vars(m)                       # Post original and lifted variables
    amp_post_lifted_constraints(m)         # Post lifted constraints
    amp_post_lifted_obj(m)                 # Post objective
    amp_post_mccormick(m)                  # Post all mccormick constraints
    # ------------------------ #
    cputime_build = time() - start_build
    m.logs[:total_time] += cputime_build
    m.logs[:time_left] = max(0.0, m.timeout - m.logs[:total_time])

    return
end

function pick_vars_discretization(m::PODNonlinearModel)
    # Figure out which are the variables that needs to be partitioned
    if m.var_discretization_algo == 0
        max_cover(m)
    elseif m.var_discretization_algo == 1
        min_vertex_cover(m)
    elseif m.var_discretization_algo == 99
        # User-defined function
        error("[You need to give me something to make this work...]Unsupported method for picking variables for discretization")
    else
        error("Unsupported method for picking variables for discretization")
    end

    return
end

function mccormick(m,xy,x,y,xˡ,xᵘ,yˡ,yᵘ)

    @constraint(m, xy >= xˡ*y + yˡ*x - xˡ*yˡ)
    @constraint(m, xy >= xᵘ*y + yᵘ*x - xᵘ*yᵘ)
    @constraint(m, xy <= xˡ*y + yᵘ*x - xˡ*yᵘ)
    @constraint(m, xy <= xᵘ*y + yˡ*x - xᵘ*yˡ)

    return
end

function mccormick_bin(m,xy,x,y)

    @constraint(m, xy <= x)
    @constraint(m, xy <= y)
    @constraint(m, xy >= x+y-1)

    return
end

function tightmccormick_monomial(m,x_p,x,xz,xˡ,xᵘ,z,p,lazy,quad) # if p=2, tightened_lazycuts = tightmccormick_quad
    if lazy == 1
        function GetLazyCuts_quad(cb)
            TOL1 = 1e-6
            if (getvalue(x)^p > (getvalue(x_p) + TOL1))
                a = p*getvalue(x)^(p-1)
                b = (1-p)*getvalue(x)^p
                @lazyconstraint(cb, a*x + b <= x_p)
            end
        end
        addlazycallback(m, GetLazyCuts_quad)
    elseif p == 2 && quad == 1
        @constraint(m, x_p >= x^2)
    else
        x0_vec = sort(union(xˡ, xᵘ))
        for x0 in x0_vec
            @constraint(m, x_p >= (1-p)*(x0)^p + p*(x0)^(p-1)*x)
        end
    end

    A = ((xᵘ).^p-(xˡ).^p)./(xᵘ-xˡ)
    @constraint(m, x_p .<= A'*xz - (A.*xˡ)'*z + ((xˡ).^p)'*z)
    return m
end

"""
    Notice there are other ways to construct partitions
"""
function add_discretization(m::PODNonlinearModel; kwargs...)

    options = Dict(kwargs)

    haskey(options, :use_solution) ? point_vec = options[:use_solution] : point_vec = m.best_bound_sol

    #===============================================================
    Consider original partition [0, 3, 7, 9], where LB/any solution is 4.
    Use ^ as the new partition, | as the original partition

    A case when discretize ratio = 4
    | -------- | - ^ -- * -- ^ ---- | -------- |
    0          3  3.5   4   4.5     7          9

    A special case when discretize ratio = 2
    | -------- | --- * --- ^ ---- | -------- |
    0          3     4     5      7          9
    ===============================================================#

    # ? Perform discretization base on type of nonlinear terms

    for i in 1:m.num_var_orig
        point = point_vec[i]
        if i in m.var_discretization_mip  # Only construct when discretized
            for j in 1:length(m.discretization[i])
                if point >= m.discretization[i][j] && point <= m.discretization[i][j+1]  # Locating the right location
                    @assert j < length(m.discretization[i])
                    lb_local = m.discretization[i][j]
                    ub_local = m.discretization[i][j+1]
                    distance = ub_local - lb_local
                    radius = distance / m.discretization_ratio
                    # lb_new = max(point - radius/2, lb_local)
                    # ub_new = min(point + radius/2, ub_local)
                    lb_new = max(point - radius, lb_local)
                    ub_new = min(point + radius, ub_local)
                    m.log_level > 99 && println("[DEBUG] VAR$(i): SOL=$(point) RATIO=$(m.discretization_ratio)   |$(round(lb_local,2)) |$(round(lb_new,2)) <- * -> $(round(ub_new,2))| $(round(ub_local,2))|")
                    # @show j, point, lb_new, ub_new, lb_local, ub_local
                    if ub_new < ub_local  # Insert new UB-based partition
                        insert!(m.discretization[i], j+1, ub_new)
                    end
                    if lb_new > lb_local  # Insert new LB-based partition
                        insert!(m.discretization[i], j+1, lb_new)
                    end
                    break
                end
            end
        end
    end

end


"""
    Use lower bound solution active interval to tight upper bound variable bounds
"""
function tighten_bounds(m::PODNonlinearModel; kwargs...)

    l_var = copy(m.l_var_orig)
    u_var = copy(m.u_var_orig)
    for i in 1:m.num_var_orig
        if i in m.var_discretization_mip
            point = m.sol_incumb_lb[i]
            for j in 1:length(m.discretization[i])
                if point >= m.discretization[i][j] && point <= m.discretization[i][j+1]
                    @assert j < length(m.discretization[i])
                    l_var[i] = m.discretization[i][j]
                    u_var[i] = m.discretization[i][j+1]
                end
            end
        elseif m.var_type_orig[i] == :Bin || m.var_type_orig[i] == :Int
            l_var[i] = round(m.sol_incumb_lb[i])
            u_var[i] = round(m.sol_incumb_lb[i])
        end
    end

    return l_var, u_var
end


"""
    Perform a minimum vertex cover for selecting variables for discretization
"""
function min_vertex_cover(m::PODNonlinearModel; kwargs...)

    # Collect the information for arcs and nodes
    nodes = Set()
    arcs = Set()
    for pair in keys(m.nonlinear_info)
        arc = []
        for i in pair
            @assert isa(i.args[2], Int)
            push!(nodes, i.args[2])
            push!(arc, i.args[2])
        end
        push!(arcs, arc)
    end
    nodes = collect(nodes)
    arcs = collect(arcs)

    # Set up minimum vertex cover problem
    minvertex = Model(solver=m.mip_solver)
    @variable(minvertex, x[nodes], Bin)
    for arc in arcs
        @constraint(minvertex, x[arc[1]] + x[arc[2]] >= 1)
    end
    @objective(minvertex, Min, sum(x))
    status = solve(minvertex, suppress_warnings=true)

    xVal = getvalue(x)

    # Getting required information
    m.num_var_discretization_mip = Int(sum(xVal))
    m.var_discretization_mip = [i for i in nodes if xVal[i] > 1e-5]

end

"""
    Collect all envolved variables as a max cover for generate discretization
"""
function max_cover(m::PODNonlinearModel; kwargs...)
    nodes = Set()
    for pair in keys(m.nonlinear_info)
        for i in pair
            @assert isa(i.args[2], Int)
            push!(nodes, i.args[2])
        end
    end
    nodes = collect(nodes)
    m.num_var_discretization_mip = length(nodes)
    m.var_discretization_mip = nodes
end
