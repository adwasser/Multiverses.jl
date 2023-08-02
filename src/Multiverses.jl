module Multiverses

using MacroTools: combinedef, postwalk, prewalk, @capture
using Tables

export Multiverse,
    choices, measurements, universes,
    choice_table, measurement_table,
    @enter, explore, explore!

"""
    Multiverse(choices, measurements, universes, choice_values, measurement_values)

A multiverse consists of different code evalutation "universes", where each universe has a set of choice values that are associated to a set of measurement values.
"""
struct Multiverse{
    T_choice<:NamedTuple,
    T_measurement<:NamedTuple,
    }
    choices::Tuple
    measurements::Tuple
    universes::Vector{Function}
    choice_values::Vector{T_choice}
    measurement_values::Vector{Union{Nothing, T_measurement}}
end

choices(m::Multiverse) = m.choices
measurements(m::Multiverse) = m.measurements
choice_table(m::Multiverse) = m.choice_values
measurement_table(m::Multiverse) = m.measurement_values
universes(m::Multiverse) = m.universes

Base.length(m::Multiverse) = length(universes(m))

Base.show(io::IO, m::Multiverse) = print(io, "Multiverse(choices = $(m.choices), measurements = $(m.measurements))")

function fix_choices(universe::Expr, choice_vals::NamedTuple)
    return postwalk(universe) do ex
        @capture(ex, @choose choice_ = foo_) || return ex
        val = choice_vals[choice]
        return Expr(:(=), choice, val)
    end
end

function track_measurements(universe::Expr, tracker)
    universe = deepcopy(universe)
    # add dictionary for tracking measurements
    insert!(universe.args, 1, :($(tracker) = Dict()))
    universe = postwalk(universe) do ex
        @capture(ex, @measure measurement_ = value_) || return ex
        qn = QuoteNode(measurement)
        Expr(
            :block,
            :($(measurement) = $(value)),
            :(setindex!($(tracker), $(measurement), $(qn)))
        )
    end
    # add return to end
    push!(universe.args, :(return $(tracker)))
    return universe
end

macro enter(block::Expr)
    if !Meta.isexpr(block, :block)
        return :(error("must enter into a block of code"))
    end
    
    # extract and validate choices and measurements
    choice_possibilities = Dict{Symbol, Vector}()
    measurements = []
    errors = []
    walked_block = postwalk(block) do ex
        if @capture(ex, @choose choice_ = p_)
            possibilities = collect((__module__).eval(p))
            if in(choice, keys(choice_possibilities))
                push!(
                    errors,
                    :(error("choice $(choice) assigned more than once"))
                )
                return ex
            end
            if length(possibilities) <= 1
                push!(
                    errors,
                    :(error("need more than possible choice"))
                )
                return ex
            end
            choice_possibilities[choice] = possibilities
            # remove macrocall to avoid counting again
            return :($(choice) = :(p))
        elseif @capture(ex, @choose foo_)
            push!(
                errors,
                :(error("need to assign possible choices, e.g., @choice x = [1, 2]"))
            )
            return ex
        elseif @capture(ex, @measure measurement_ = foo_)
            if in(measurement, measurements)
                push!(
                    errors,
                    :(error("measurement $(measurement) assigned more than once"))
                )
                return ex
            end
            push!(measurements, measurement)
            return :($(measurement) = $(foo))
        elseif @capture(ex, @measure foo_)
            push!(
                errors,
                :(error("need to assign a value to the measurement , e.g., @measure y = x + 2"))
            )
            return ex
        end
        return ex
    end
    if length(errors) > 0
        return first(errors)
    end
    
    choices = tuple(keys(choice_possibilities)...)
    if length(choices) < 1
        return :(error("need at least one choice"))
    end
    measurements = tuple(measurements...)
    if length(measurements) < 1
        return :(error("need at least one measurement"))
    end
    overlap = intersect(choices, measurements)
    if length(overlap) > 0
        return :(error("$(overlap) variables found in both choices and measurements"))
    end
    
    # generate choice value sets
    possibilities = [choice_possibilities[choice] for choice in choices]
    choice_types = eltype.(possibilities)
    T_choice = NamedTuple{choices, Tuple{choice_types...}}
    choice_values = Vector{T_choice}()
    for vals in Iterators.product(possibilities...)
        push!(choice_values, NamedTuple{choices}(vals))
    end

    # generate universe functions
    universes = []
    for vals in choice_values
        universe = deepcopy(block)
        universe = fix_choices(universe, vals)
        tracker = (__module__).gensym()
        universe = track_measurements(universe, tracker)
        def = combinedef(
            Dict(
                :name => (__module__).gensym(),
                :body => universe,
                :args => (),
                :kwargs => (),
            )
        )
        push!(universes, (__module__).eval(def))
    end
    
    T_measurement = NamedTuple{measurements}
    measurement_values = [nothing for i in 1:length(universes)]
    m = Multiverse{T_choice, T_measurement}(
        choices, measurements, universes,
        choice_values, measurement_values
    )
    return m
end

function explore(m::Multiverse, i)
    universe_function = universes(m)[i]
    d = universe_function()
    return NamedTuple(k => get(d, k, missing) for k in m.measurements)
end

function explore!(m::Multiverse, i)
    m.measurement_values[i] = explore(m, i)
    return m
end

function explore!(m::Multiverse)
    for i in 1:length(m)
        explore!(m, i)
    end
    return m
end

Tables.istable(::Multiverse) = true
Tables.rowaccess(::Multiverse) = true
Tables.rows(m::Multiverse) = map(
    x -> merge(x...),
    zip(choice_table(m), measurement_table(m))
)

end # module Multiverses
