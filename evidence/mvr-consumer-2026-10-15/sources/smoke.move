module consumer::smoke { use turbospump::curves; public fun quote(a: u64,s: u64,t: u64): u64 { curves::calculate_token_return(a,s,t) } }
