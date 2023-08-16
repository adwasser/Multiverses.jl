using Test

using Tables

using Multiverses

m = @enter begin
    @choose x = [1, 2]
    @measure y = x + 3
end

@testset "entering multiverse" begin

    @test isa(m, Multiverse)
    @test in(:x, choices(m))
    @test length(choices(m)) == 1
    @test in(:y, measurements(m))
    @test length(measurements(m)) == 1
    @test length(m) == 2
    @test in((x = 1,), choice_table(m))
    @test all(isnothing.(measurement_table(m)))
    
    explore!(m)
    @test !any(isnothing.(measurement_table(m)))
    @test in((y = 4,), measurement_table(m))
    @test in((x = 1, y = 4), Tables.rows(m))

end


m = @enter begin
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
    
    @measure mean_c = sum(c) / length(c)
    if a_threshold == 0
        @measure flag_zeros = true
    end
end
explore!(m)

@testset "nested choices" begin
    @test in(:a_threshold, choices(m))
    @test in(:b_threshold, choices(m))
    @test length(choices(m)) == 2
    for row in Tables.rows(m)
        if row.a_threshold == 0
            @test row.flag_zeros
        else
            @test ismissing(row.flag_zeros)
        end
    end
end


@testset "helpful errors" begin

    # lack of assignment in choice
    @test_throws ErrorException @macroexpand @enter begin
        @choose 1 + 2
        @measure 3
    end

    # lack of assignment in measurement
    @test_throws ErrorException @macroexpand @enter begin
        @choose x = [1, 2]
        @measure x + 3
    end

    # lack of possibilities in choice
    @test_throws ErrorException @macroexpand @enter begin
        @choose x = 1
        @measure y = x + 2
    end

    # duplicate choices
    @test_throws ErrorException @macroexpand @enter begin
        @choose x = [1, 2]
        @choose x = [4, 5]
        @measure y = 2 * x
    end

    # duplicate measurements
    @test_throws ErrorException @macroexpand @enter begin
        @choose x = [1, 2]
        @measure y = x + 1
        @measure y = x + 3
    end

    # overlap between choice and measurement
    @test_throws ErrorException @macroexpand @enter begin
        @choose x = [1, 2]
        @measure x = x + 2
    end
end
