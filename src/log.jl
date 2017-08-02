# Create dictionary of logs for timing and iteration counts
function create_logs!(m)

    logs = Dict{Symbol,Any}()

    # Timers
    logs[:presolve_time] = 0.       # Total presolve-time of the algorithm
    logs[:total_time] = 0.          # Total run-time of the algorithm
    logs[:time_left] = m.timeout    # Total remaining time of the algorithm if timeout is specified

    # Values
    logs[:obj] = []                 # Iteration based objective
    logs[:bound] = []               # Iteration based objective

    # Counters
    logs[:n_iter] = 0               # Number of iterations in iterative
    logs[:n_feas] = 0               # Number of times get a new feasible solution
    logs[:ub_incumb_cnt] = 0        # Number of incumbents detected on upper bound
    logs[:lb_incumb_cnt] = 0        # Number of incumebnts detected on lower bound
    logs[:bt_iter] = 0

    m.logs = logs
end

function logging_summary(m::PODNonlinearModel)
    if m.log_level > 0
        @printf "full problem loaded into POD.\n"
        @printf "number of constraints = %d.\n" m.num_constr_orig
        @printf "number of non-linear constraints = %d.\n" m.num_nlconstr_orig
        @printf "number of linear constraints = %d.\n" m.num_lconstr_orig
        @printf "number of variables = %d.\n" m.num_var_orig

        println("NLP solver = ", split(string(m.nlp_local_solver),".")[1])
        println("MIP solver = ", split(string(m.mip_solver),".")[1])

        println("regulated maximum solution time = ", m.timeout)
        println("regulated maximum iterations =  ", m.maxiter)
        @printf "relative optimality gap criteria = %.5f (%.4f %%)\n" m.rel_gap (m.rel_gap*100)
        println("detected nonlinear terms = $(length(m.nonlinear_terms))")
        println("number of variables involved in nonlinear terms = $(length(m.all_nonlinear_vars))")
        println("algorithm for selecting variables to discretize = $(m.discretization_var_pick_algo)")
        println("number of selected variables to discretize = $(length(m.var_discretization_mip))")
    end
end

function logging_head()
    println(" | NLP         | MIP         || Objective   | Bound       | GAP\%        | CLOCK       | TIME LEFT   | Iter   ")
end

function logging_row_entry(m::PODNonlinearModel; kwargs...)
    b_len = 12
    if isa(m.logs[:obj][end], Float64)
        UB_block = string(" ", round(m.logs[:obj][end],4), " " ^ (b_len - length(string(round(m.logs[:obj][end], 4)))))
    else
        UB_block = string(" ", string(m.logs[:obj][end]), " " ^ (b_len - length(string(m.logs[:obj][end]))))
    end
    LB_block = string(" ", round(m.logs[:bound][end],4), " " ^ (b_len - length(string(round(m.logs[:bound][end], 4)))))
    incumb_UB_block = string(" ", round(m.best_obj,4), " " ^ (b_len - length(string(round(m.best_obj, 4)))))
    incumb_LB_block = string(" ", round(m.best_bound,4), " " ^ (b_len - length(string(round(m.best_bound, 4)))))
    GAP_block = string(" ", round(m.best_rel_gap*100,5), " " ^ (b_len - length(string(round(m.best_rel_gap*100,5)))))
    UTIME_block = string(" ", round(m.logs[:total_time],2), "s", " " ^ (b_len - 1 - length(string(round(m.logs[:total_time],2)))))
    LTIME_block = string(" ", round(m.logs[:time_left],2), "s", " " ^ (b_len - 1 - length(string(round(m.logs[:time_left],2)))))
    ITER_block = string(" ", m.logs[:n_iter])
    println(" |",UB_block,"|",LB_block,"||",incumb_UB_block,"|",incumb_LB_block,"|",GAP_block,"|",UTIME_block,"|",LTIME_block,"|",ITER_block)
end


#=========================================================
 Logging and printing functions
=========================================================#

# Create dictionary of statuses for POD algorithm
function create_status!(m)

    status = Dict{Symbol,Symbol}()

    status[:presolve] = :none                   # Status of presolve
    status[:local_solve] = :none                # Status of local solve
    status[:bounding_solve] = :none              # Status of bounding solve
    status[:lower_bounding_solve] = :none        # Status of lower bonding solve
    status[:upper_bounding_solve] = :none       # Status of bounding solve
    status[:feasible_solution] = :none          # Status of whether a upper bound is detected or not
    status[:upper_bound] = :none                # Status of whether a upper bound has been detected
    status[:lower_bound] = :none                # Status of whether a lower bound has been detected
    status[:bound] = :none                      # Status of whether a bound has been detected
    status[:bound_tightening_solve] = :none    # Status of bound-tightening solve

    m.status = status
end

function summary_status(m::PODNonlinearModel)

    if m.status[:bound] == :Detected && m.status[:feasible_solution] == :Detected
        if m.best_rel_gap > m.rel_gap
            m.pod_status = :UserLimits
        else
            m.pod_status = :Optimal
        end
    elseif m.status[:bound] == :Detected && m.status[:feasible_solution] == :none
        m.pod_status = :Infeasible
    elseif m.status[:bound] == :none && m.status[:feasible_solution] == :Detected
        m.pod_status = :Heuristic
    else
        error("[UNEXPECTED] Missing bound and feasible solution during status summary.")
    end
end
