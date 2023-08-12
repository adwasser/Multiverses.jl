module Multiverses

using MacroTools: combinedef, postwalk, prewalk, @capture
using Tables

export Multiverse,
    @enter, @explore, explore, explore!,
    choices, measurements, universes,
    choice_table, measurement_table

"""
    Multiverse(choices, measurements, universes, choice_values, measurement_values)

A multiverse consists of different code evalutation "universes", where each universe has a set of choice values that are associated to a set of measurement values.
"""
struct Multiverse
    choices::Tuple
    measurements::Tuple
    universes::Vector{Function}
    choice_values::Vector{NamedTuple}
    measurement_values::Vector{Union{Nothing, NamedTuple}}
end

function Multiverse(choices, measurements, universes, choice_values)
    measurement_values = Vector{Union{Nothing, NamedTuple}}()
    for i in 1:length(choice_values)
        push!(measurement_values, nothing)
    end
    return Multiverse(
        choices, measurements, universes, choice_values, measurement_values
    )
end

choices(m::Multiverse) = m.choices
measurements(m::Multiverse) = m.measurements
universes(m::Multiverse) = m.universes
choice_table(m::Multiverse) = m.choice_values
measurement_table(m::Multiverse) = m.measurement_values

Base.length(m::Multiverse) = length(universes(m))

Base.show(io::IO, m::Multiverse) = print(io, "Multiverse(choices = $(m.choices), measurements = $(m.measurements))")

function generate_choice_values(choices, choice_possibilities)
    possibilities = [choice_possibilities[choice] for choice in choices]
    choice_types = eltype.(possibilities)
    T_choice = NamedTuple{choices, Tuple{choice_types...}}
    choice_values = Vector{T_choice}()
    for vals in Iterators.product(possibilities...)
        push!(choice_values, NamedTuple{choices}(vals))
    end
    return choice_values
end

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

function generate_universes(block::Expr, choice_values)
    universes = gensym()
    expressions = Vector{Any}()
    push!(expressions, Expr(:(=), universes, :([])))
    for vals in choice_values
        universe = deepcopy(block)
        universe = fix_choices(universe, vals)
        tracker = gensym()
        universe = track_measurements(universe, tracker)
        def = combinedef(
            Dict(
                :name => gensym(),
                :body => universe,
                :args => (),
                :kwargs => (),
            )
        )
        push!(expressions, Expr(:call, :push!, universes, def))
    end
    push!(expressions, universes)
    return Expr(:block, expressions...)
end

function validate_block(mod, block::Expr)
    # extract and validate choices and measurements
    choice_possibilities = Dict{Symbol, Vector}()
    measurements = []
    walked_block = postwalk(block) do ex
        if @capture(ex, @choose choice_ = p_)
            possibilities = collect(mod.eval(p))
            if in(choice, keys(choice_possibilities))
                error("choice $(choice) assigned more than once")
            end
            if length(possibilities) <= 1
                error("need more than possible choice")
            end
            choice_possibilities[choice] = possibilities
            # remove macrocall to avoid counting again
            return :($(choice) = :(p))
        elseif @capture(ex, @choose foo_)
            error("need to assign possible choices, e.g., @choice x = [1, 2]")
        elseif @capture(ex, @measure measurement_ = foo_)
            if in(measurement, measurements)
                error("measurement $(measurement) assigned more than once")
            end
            push!(measurements, measurement)
            return :($(measurement) = $(foo))
        elseif @capture(ex, @measure foo_)
            error("need to assign a value to the measurement , e.g., @measure y = x + 2")
        end
        return ex
    end
    choices = collect(keys(choice_possibilities))
    # some additional validation
    if length(choices) < 1
        error("need at least one choice")
    end
    measurements = tuple(measurements...)
    if length(measurements) < 1
        error("need at least one measurement")
    end
    overlap = intersect(choices, measurements)
    if length(overlap) > 0
        error("$(overlap) variables found in both choices and measurements")
    end
    return (choice_possibilities, measurements)
end


function enter(mod, block::Expr)
    if !Meta.isexpr(block, :block)
        error("must enter into a block of code")
    end
    
    choice_possibilities, measurements = validate_block(mod, block)
    choices = tuple(keys(choice_possibilities)...)
    
    choice_values = generate_choice_values(choices, choice_possibilities)
    universes = generate_universes(block, choice_values)

    sym = mod.gensym()
    return Expr(
        :block,
        Expr(:(=), sym, universes),
        Expr(
            :call,
            :Multiverse,
            choices,
            measurements,
            sym,
            choice_values,
        )
    )
end

"""
    multiverse = @enter begin
        @choose x = 1:5
        y = 2 * x + 3
        @measure z = sqrt(y)
    end

Prepare a multiverse analysis based on the provided block of code.

Choices are denoted by the `@choose` macrocall and must assign a collection to
a variable. Measurements are denoted by the `@measure` macrocall and must
assign a value to a variable.

The multiverse can have the measurements in each choice-set universe populated
using the `explore!` method, either all at once or iteratively.
"""
macro enter(block::Expr)
    return esc(enter(__module__, block))
end

"""
    multiverse = @explore begin
        @choose x = 1:5
        y = 2 * x + 3
        @measure z = sqrt(y)
    end

Prepare and run a multiverse analysis.
"""
macro explore(block)
    return Expr(
        :call,
        :explore!,
        esc(enter(__module__, block))
    )
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
