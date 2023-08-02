using Test
using Statistics
using Random

using Tables

using Multiverses

@testset "entering multiverse" begin

    m = @enter begin
        @choose x = [1, 2]
        @measure y = x + 3
    end

    @assert isa(m, Multiverse)
    @assert in(:x, choices(m))
    @assert length(choices(m)) == 1
    @assert in(:y, measurements(m))
    @assert length(measurements(m)) == 1
    @assert length(m) == 2
    @assert in((x = 1,), choice_table(m))
    @assert all(isnothing.(measurement_table(m)))
    
    explore!(m)
    @assert !any(isnothing.(measurement_table(m)))
    @assert in((y = 4,), measurement_table(m))
    @assert in((x = 1, y = 4), Tables.rows(m))

end


@testset "nested choices" begin
    
    m = @enter begin
        Random.seed!(1234)
        data = [(a = randn(), b = randn(), c = randn()) for i in 1:100]
        @choose a_threshold = [-0.5, 0.0, 0.5]
        b_outer_threshold = if a_threshold > 0
            @choose b_threshold = [-0.5, 0.0, 0.5]
        else
            0.0
        end

        subset_data = filter(
            row -> (row.a > a_threshold) && (row.b > b_outer_threshold),
            data
        )
        c = map(row -> row.c, subset_data)
        
        @measure mean_c = mean(c)
        @measure std_c = std(c)
        @measure z_c = mean_c / std_c
        if a_threshold == 0
            @measure flag_zeros = true
        end
    end
    explore!(m)
    
    @assert in(:a_threshold, choices(m))
    @assert in(:b_threshold, choices(m))
    @assert length(choices(m)) == 2
    for row in Tables.rows(m)
        if row.a_threshold == 0
            @assert row.flag_zeros
        else
            @assert ismissing(row.flag_zeros)
        end
    end
end


@testset "helpful errors" begin

    # lack of assignment in choice
    @test_throws Exception @enter begin
        @choose 1 + 2
        @measure 3
    end

    # lack of assignment in measurement
    @test_throws Exception @enter begin
        @choose x = [1, 2]
        @measure x + 3
    end

    # lack of possibilities in choice
    @test_throws Exception @enter begin
        @choose x = 1
        @measure y = x + 2
    end

    # duplicate choices
    @test_throws Exception @enter begin
        @choose x = [1, 2]
        @choose x = [4, 5]
        @measure y = 2 * x
    end

    # duplicate measurements
    @test_throws Exception @enter begin
        @choose x = [1, 2]
        @measure y = x + 1
        @measure y = x + 3
    end

    # overlap between choice and measurement
    @test_throws Exception @enter begin
        @choose x = [1, 2]
        @measure x = x + 2
    end
end
