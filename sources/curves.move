module turbospump::curves {
    use turbospump::full_math_u64;

    // Calculate the cost of sui based on the current reserves and desired amount
    // sui cost = （ReserveSUI * ReserveToken) / (ReserveToken - tokenAmountToBuy) - ReserveSUI
    public fun calculate_liquidity_cost(
        currentReserveSUI: u64, 
        currentReserveToken: u64, 
        tokenAmountToBuy: u64
    ) : u64 {
        full_math_u64::mul_div_ceil(
            currentReserveSUI,
            currentReserveToken,
            currentReserveToken - tokenAmountToBuy,
        ) - currentReserveSUI
    }
    
    // Calculate the amount of SUI received when removing liquidity given the current reserves
    // sui return = ReserveSUI - (ReserveSUI * ReserveToken) / (ReserveToken + tokenAmountToSell)
    public fun calculate_sui_return(
        tokenAmountToSell: u64,
        currentReserveSUI: u64, 
        currentReserveToken: u64, 
    ): u64 {
        currentReserveSUI - full_math_u64::mul_div_ceil(
            currentReserveSUI,
            currentReserveToken,
            currentReserveToken + tokenAmountToSell,
        )
    }
    
    // Calculate the amount of tokens received based on the input SUI amount and current reserves
    // token return = ReserveToken - (ReserveSUI * ReserveToken) / (ReserveSUI + suiAmountToSell)
    public fun calculate_token_return(
        suiAmountToSell: u64, 
        currentReserveSUI: u64,
        currentReserveToken: u64, 
    ) : u64 {
        currentReserveToken - full_math_u64::mul_div_ceil(
            currentReserveSUI,
            currentReserveToken,
            currentReserveSUI + suiAmountToSell,
        )
    }
}