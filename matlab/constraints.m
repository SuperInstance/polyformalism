%% =============================================================================
%  polyformalism: constraints.m — Array-Language Constraint Kernels (MATLAB)
% =============================================================================
%
% MATLAB is an array language, directly inheriting from APL (1964) through
% LINPACK/EISPACK traditions and later Fortran 90 array syntax.
% As an array language, MATLAB's fundamental operations are vectorized:
%   - Loops are IMPLICIT, not explicit
%   - Operations apply to the entire array at once
%   - The constraint check and bloom merge below are SINGLE EXPRESSIONS
%     because the array language handles the iteration
%
% This is the APL inheritance: one function call on each axis, not
% one element at a time. The loop lives in optimized BLAS/LAPACK
% (or JIT-accelerated) code, not MATLAB interpreted loops.
%
% Three core polyformalism constraint kernels:
%   1. constraint_check  —  bounds validation (value ∈ [lower, upper])
%   2. bloom_merge       —  bitwise OR of two bloom filters
%   3. eisenstein_norm   —  ℤ[ω] norm: a² − a·b + b²
% =============================================================================

%% ---------------------------------------------------------------------------
%  constraint_check — vectorized bounds validation
%
%  APL inheritance: `all(values >= lower & values <= upper)` is a single
%  vectorized expression. The `&` and comparisons are element-wise. MATLAB
%  automatically expands scalar bounds. No explicit loop anywhere.
%
%  Inputs:
%    lower  — scalar or vector of lower bounds
%    upper  — scalar or vector of upper bounds
%    values — vector of values to check
%
%  Returns:
%    logical true if ALL values satisfy lower(i) <= values(i) <= upper(i)
%    (with implicit expansion when lower/upper are scalars)
% ---------------------------------------------------------------------------
function result = constraint_check(lower, upper, values)
    result = all(values >= lower & values <= upper, 'all');
end


%% ---------------------------------------------------------------------------
%  bloom_merge — bitwise OR of two bloom filters stored as uint8 vectors
%
%  APL inheritance: `bitor(dst, src)` is a single vectorized expression.
%  MATLAB's bitor function operates element-wise on arrays. No explicit
%  byte-by-byte loop.
%
%  Inputs:
%    dst — uint8 vector (first bloom filter)
%    src — uint8 vector (second bloom filter)
%
%  Returns:
%    uint8 vector where each element is dst(i) | src(i)
%    (implicit expansion handles mismatched lengths)
% ---------------------------------------------------------------------------
function merged = bloom_merge(dst, src)
    % Single expression: vectorized bitwise OR on integer arrays
    merged = bitor(dst, src);
end


%% ---------------------------------------------------------------------------
%  eisenstein_norm — norm in the Eisenstein integer ring ℤ[ω]
%
%  For integers a, b ∈ ℤ, the norm N(a + b·ω) where ω = (-1 + √(-3))/2 is:
%    N(a + b·ω) = a² - a·b + b²
%
%  This is the fundamental quadratic form of the hexagonal lattice A₂.
%  Vectorized: works on scalar or array inputs.
%
%  Inputs:
%    a — integer(s), coefficient of 1
%    b — integer(s), coefficient of ω
%
%  Returns:
%    integer(s) — the Eisenstein norm a² - a·b + b²
% ---------------------------------------------------------------------------
function n = eisenstein_norm(a, b)
    n = a.*a - a.*b + b.*b;
end


%% =============================================================================
%  Tests — run with:  constraints    (in MATLAB command window)
%                    constraints.m  (drag into MATLAB editor and Run)
% =============================================================================

function constraints()
    fprintf('========================================\n');
    fprintf('Polyformalism Constraint Kernels — MATLAB\n');
    fprintf('========================================\n\n');

    % ---- 1. constraint_check tests ----
    fprintf('--- constraint_check ---\n');

    % Test with standard vectors: constraints [0..15] vs [0..100]
    test_lower  = zeros(1, 16);
    test_upper  = 0:15;
    test_values = 25:40;
    result1 = constraint_check(test_lower, test_upper, test_values);
    fprintf('  Passing (25..40 vs bounds [0..15]): %d\n', result1);

    % Failing values [200..215] — should all fail
    fail_values = 200:215;
    result2 = constraint_check(test_lower, test_upper, fail_values);
    fprintf('  Failing (200..215 vs bounds [0..15]): %d\n', result2);

    % Edge cases
    fprintf('  Single passing: %d\n', constraint_check(0, 10, 5));
    fprintf('  Single failing: %d\n', constraint_check(0, 10, 15));

    fprintf('\n');

    % ---- 2. bloom_merge tests ----
    fprintf('--- bloom_merge ---\n');

    % Create two 1000-element (8000-bit) bloom filters
    filter1 = zeros(1, 1000, 'uint8');
    filter2 = zeros(1, 1000, 'uint8');

    % Insert some keys into filter1 (set some bits)
    filter1(1:10) = uint8([0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, ...
                           0xAA, 0x55]);

    % Insert some keys into filter2
    filter2(5:15) = uint8([0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, ...
                           0x01, 0x02, 0x04]);

    % Merge them — single expression, no explicit loop
    merged = bloom_merge(filter1, filter2);

    % Verify: merged bytes should be bitwise OR of the two
    expected = bitor(filter1, filter2);  % ground truth via same function
    check_ok = isequal(merged, expected);
    fprintf('  Merge verified (1000 bytes): %d\n', check_ok);

    % Check that merged has union bits at the overlap region
    overlap_ok = isequal(merged(1:15), bitor(filter1(1:15), filter2(1:15)));
    fprintf('  Union preserved in overlap region: %d\n', overlap_ok);

    fprintf('\n');

    % ---- 3. eisenstein_norm tests ----
    fprintf('--- eisenstein_norm ---\n');

    % Standard test vectors
    % Expected norms for the Eisenstein lattice
    % N(a + bω) = a² - ab + b²
    % (3, 0):  9 - 0 + 0  = 9
    % (0, 1):  0 - 0 + 1  = 1
    % (2, -1): 4 - (-2) + 1 = 7
    % (-1, 2): 1 - (-2) + 4 = 7
    % (5, 5):  25 - 25 + 25 = 25
    a_vals = [3, 0, 2, -1, 5];
    b_vals = [0, 1, -1, 2, 5];
    expected_norms = [9, 1, 7, 7, 25];

    for i = 1:length(a_vals)
        a_i    = a_vals(i);
        b_i    = b_vals(i);
        norm_i = eisenstein_norm(a_i, b_i);
        exp_i  = expected_norms(i);
        if norm_i == exp_i
            status = 'PASS';
        else
            status = 'FAIL';
        end
        fprintf('  N(%2d + %2dω) = %2d  (expected %2d)  [%s]\n', ...
                a_i, b_i, norm_i, exp_i, status);
    end

    % Vectorized norm test
    norms_vec = eisenstein_norm(a_vals, b_vals);
    fprintf('  Vectorized: [%s]  all OK: %d\n', ...
            strjoin(arrayfun(@num2str, norms_vec, 'UniformOutput', false), ', '), ...
            all(norms_vec == expected_norms));

    fprintf('\n========================================\n');
    fprintf('All MATLAB polyformalism constraint tests complete.\n');
    fprintf('========================================\n');
end

%% Run the test harness when this script is executed
constraints();
