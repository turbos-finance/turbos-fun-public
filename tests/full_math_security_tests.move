// Copyright (c) Turbos Finance, Inc.
// SPDX-License-Identifier: MIT

#[test_only]
module turbospump::full_math_security_tests {
    use turbospump::full_math_u64;

    #[test]
    fun floor_round_ceil_and_zero() {
        assert!(full_math_u64::mul_div_floor(5, 3, 2) == 7, 99);
        assert!(full_math_u64::mul_div_round(5, 3, 2) == 8, 99);
        assert!(full_math_u64::mul_div_ceil(5, 3, 2) == 8, 99);
        assert!(full_math_u64::mul_div_round(2, 2, 3) == 1, 99);
        assert!(full_math_u64::mul_div_round(5, 1, 3) == 2, 99);
        assert!(full_math_u64::mul_div_floor(0, 5, 1) == 0, 99);
        assert!(full_math_u64::mul_div_round(0, 5, 1) == 0, 99);
        assert!(full_math_u64::mul_div_ceil(0, 5, 1) == 0, 99);
    }

    #[test]
    fun exact_division_and_u64_limit() {
        let m = 18446744073709551615;
        assert!(full_math_u64::mul_div_floor(m, m, m) == m, 99);
        assert!(full_math_u64::mul_div_round(m, m, m) == m, 99);
        assert!(full_math_u64::mul_div_ceil(m, m, m) == m, 99);
        assert!(full_math_u64::full_mul(m, m) == (m as u128) * (m as u128), 99);
    }

    #[test]
    fun shifts_with_representable_results() {
        assert!(full_math_u64::mul_shr(5, 3, 1) == 7, 99);
        assert!(full_math_u64::mul_shl(5, 3, 1) == 30, 99);
        assert!(full_math_u64::mul_shr(5, 3, 0) == 15, 99);
        assert!(full_math_u64::mul_shl(5, 3, 0) == 15, 99);
        assert!(full_math_u64::mul_shr(18446744073709551615, 18446744073709551615, 64) == 18446744073709551614, 99);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun floor_rejects_zero_denominator() {
        full_math_u64::mul_div_floor(1, 1, 0);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun round_rejects_zero_denominator() {
        full_math_u64::mul_div_round(1, 1, 0);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun ceil_rejects_zero_denominator() {
        full_math_u64::mul_div_ceil(1, 1, 0);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun floor_rejects_quotient_overflow() {
        full_math_u64::mul_div_floor(18446744073709551615, 2, 1);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun round_rejects_quotient_overflow() {
        full_math_u64::mul_div_round(18446744073709551615, 2, 1);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun ceil_rejects_quotient_overflow() {
        full_math_u64::mul_div_ceil(18446744073709551615, 2, 1);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun shift_right_rejects_invalid_shift() {
        full_math_u64::mul_shr(1, 1, 128);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun shift_left_rejects_invalid_shift() {
        full_math_u64::mul_shl(1, 1, 128);
    }

    #[test, expected_failure(arithmetic_error, location = turbospump::full_math_u64)]
    fun shift_left_rejects_u64_result_overflow() {
        full_math_u64::mul_shl(9223372036854775808, 1, 1);
    }
}
