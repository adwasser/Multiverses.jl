# Multiverses.jl

A multiverse analysis aims to investigate the robustness of a scientific claim to variations in the data analysis process, such as choices in the measurement process or statistical modeling.
Each set of choices defines a distinct "universe" with potentially different results or conclusions.

This Julia package provides a set of macro functions for taking some arbitrary Julia code and re-running the code under different possible assignment choices.

For more background and practical guidance for use, see some of the following articles:

* Del Giudice and Gangestad (2021): [A Traveler’s Guide to the Multiverse: Promises, Pitfalls, and a Framework for the Evaluation of Analytic Decisions](https://journals.sagepub.com/doi/10.1177/2515245920954925)
* Simonsohn et al. (2018): [Specification Curve: Descriptive and Inferential Statistics on All Reasonable Specifications](https://urisohn.com/sohn_files/wp/wordpress/wp-content/uploads/Paper-Specification-curve-2018-11-02.pdf)
* Steegan et al. (2016): [Increasing Transparency Through a Multiverse Analysis](https://journals.sagepub.com/doi/10.1177/1745691616658637)

See also the closely related R package, [multiverse](https://github.com/MUCollective/multiverse/).

# Basic usage

Below is a contrived example to demonstrate the basic usage.

```julia
n = 100
x_data = randn(n)
y_data = randn(n)
z_data = randn(n)

x_threshold = 0.3
y_threshold = -0.5

pick = (x_data .> x_threshold) .&& (y_data .> y_threshold)
z_subset = z_data[pick]
mean_z = sum(z_subset) / length(z_subset)
```			

In the code above, we have some set of x, y, z points, and we measure the mean of the z values for a subset of points determined by chosen thresholds on x and y.
We could turn this into a multiverse analysis as follows.

```julia
using Multiverses

n = 100
x_data = randn(n)
y_data = randn(n)
z_data = randn(n)

multiverse = @explore begin
    @choose x_threshold = [-0.5, -0.25, 0, 0.25, 0.5]
    @choose y_threshold = [-0.5, -0.25, 0, 0.25, 0.5]
    pick = (x_data .> x_threshold) .&& (y_data .> y_threshold)
    z_subset = z_data[pick]
    @measure mean_z = sum(z_subset) / length(z_subset)
end
```

In the example above, we have surrounded the analysis code within the `@explore` block.
Within the code block, we specified two choices with the`@choice` macro.
Note that a choice has to assign a collection to a variable.
We have also specified one result with the `@measure` macro.

When constructing this multiverse, we first look for all choices made (`x_threshold` and `y_threshold`), and collect the possible values for each choice (here both consist of a list of the same five numbers).
Then we construct the list with the set of all possible choices (i.e., the Cartesian product of the choice sets).
Finally, we iteratively pick the next possible set of choices, evaluate the analysis when assigning those choices, and keep track of the associated measurement results.

The returned object (called `multiverse` in the example), has the type `Multiverse`, and the package provides the accessor methods `choices`, `measurements`, `choice_table`, and `measurement_table`.
The first two methods return the tuple of choice and measurement symbols for the analysis (e.g., `(:x_threshold, :y_threshold)` and `(:mean_z,)` respectively, in this example).
The last two methods each provide a vector of named tuples.
A row in the table corresponds to one universe within the multiverse analysis, representing a distinct set of choices made, and the corrsponding measurement values.

The `Multiverse` type also supports the [Tables.jl](https://tables.juliadata.org/stable/) interface, so you can do, e.g., `DataFrame(multiverse)` to get a data frame with the contents of both the choice table and the measurement table all together.

At this point, you can plot and analyze the associations between the choices and the measurement results using your preferred plotting and statistical tools.
Specific guidance for what to look at (e.g., specification curves, p-value distributions, v

## Advanced usage

The behavior of the `@explore` macro is to find all choice sets and then immediately evaluate each universe.
For any moderately complicated or slow-to-compute analysis, you may want more fine-grained control over the evaluation process.
For instance, you might want to randomly sample the choice sets, cache results to disk for a long running computation, or simply include a [progress meter](https://github.com/timholy/ProgressMeter.jl).

The `@enter` macro constructs a `Multiverse` object from a code block analogously to the `@explore` macro, but it does not yet evaluate any of the universes.
By default, the measurement values will all be `nothing`.

You can selectively run and store the measurement results of a universe with the `explore!` method as follows:

```julia
m = @enter begin
    @choose x = 1:10
    @measure y = x + 42
end
for i in 1:length(m)
    explore!(m, i)
end
```

## Implementation details

The only macros exported by this package are `@explore` and `@enter`.
The `@choice` and `@measure` macros are not actually defined macro functions; rather they are merely syntax used to construct the analysis.

Note that the right-hand side of the choice assignment will be evaluated in the scope of the macro-calling module at the time of macro expansion.
This is to allow for an arbitrary expression returning a collection to be used, rather than just a literal vector or tuple.
All other code evaluation is currently postponed to until after the macro has been expanded.
