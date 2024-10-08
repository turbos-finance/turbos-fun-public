module turbospump::turbospump {
    use turbospump::curves;
    use turbospump::full_math_u64;
    use std::ascii;
    use std::type_name;
    use sui::clock;
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field;
    use sui::event;
    use sui::sui::{SUI};
    use sui::balance::{Self, Balance};

    const CURRENT_VERSION: u64 = 1; 
    const FEE_RATE_SCALE: u64 = 1_000_000;

    //errors
    const EWrongVersion: u64 = 0;
    const EIncorrectLP: u64 = 1;
    const EIncorrectCoinAmount: u64 = 2;
    const EPoolNotCompleted: u64 = 3;
    const EInvalidCreateParams: u64 = 4;
    const EInvalidCoinTreasuryCap: u64 = 5;
    const EAmountOutBelowMinimum: u64 = 6; 
    const EAmountInAboveMaximum: u64 = 7; 
    const ESuiAmountNotEnough: u64 = 8; 
    const ETokenReservesNotEnough: u64 = 9; 
    const ESuiReservesNotEnough: u64 = 10; 

    public struct AdminCap has store, key {
	    id: UID
    }

    public struct Configuration has store, key {
        id: object::UID,
        version: u64,
        admin: address,
        platform_fee: u64,
        graduated_fee: u64,
        initial_virtual_sui_reserves: u64,
        initial_virtual_token_reserves: u64,
        remain_token_reserves: u64,
        token_decimals: u8,
        protocol_vault: Balance<SUI>,
        fair_launch_sui_amount: u64,
    }
    
    public struct Pool<phantom T> has store, key {
        id: object::UID,
        real_sui_reserves: Balance<SUI>,
        real_token_reserves: Balance<T>,
        virtual_token_reserves: u64,
        virtual_sui_reserves: u64,
        remain_token_reserves: Balance<T>,
        is_completed: bool,
    }

    public struct SetPackageVersion has copy, drop {
	    new_version: u64,
	    old_version: u64
    }

    public struct InitConfigEvent has copy, drop {
	    admin_cap_id: ID,
	    config_id: ID
    }
    
    public struct ConfigChangedEvent has copy, drop, store {
        platform_fee: u64,
        graduated_fee: u64,
        initial_virtual_sui_reserves: u64,
        initial_virtual_token_reserves: u64,
        remain_token_reserves: u64,
        token_decimals: u8,
        fair_launch_sui_amount: u64,
    }
    
    public struct CreatedEvent has copy, drop, store {
        name: ascii::String,
        symbol: ascii::String,
        uri: ascii::String,
        description: ascii::String,
        twitter: ascii::String,
        telegram: ascii::String,
        website: ascii::String,
        token_address: ascii::String,
        bonding_curve: ascii::String,
        pool_id: object::ID,
        created_by: address,
        real_sui_reserves: u64,
        real_token_reserves: u64,
        virtual_sui_reserves: u64,
        virtual_token_reserves: u64,
        remain_token_reserves: u64,
        is_completed: bool,
        deployment_fee: u64,
    }
    
    public struct PoolCompletedEvent has copy, drop, store {
        token_address: ascii::String,
        lp: ascii::String,
    }
    
    public struct TradedEvent has copy, drop, store {
        is_buy: bool,
        user: address,
        token_address: ascii::String,
        sui_amount: u64,
        token_amount: u64,
        fee_amount: u64,
        real_sui_reserves: u64,
        real_token_reserves: u64,
        virtual_sui_reserves: u64,
        virtual_token_reserves: u64,
        remain_token_reserves: u64,
        is_completed: bool,
        pool_id: object::ID,
    }

    public struct OwnershipTransferredEvent has copy, drop, store {
        old_admin: address,
        new_admin: address,
    }

    fun init(txContext: &mut tx_context::TxContext) {
        let admin_cap= AdminCap {
            id: object::new(txContext),
        };
        let config = Configuration{
            id                             : object::new(txContext), 
            version                        : 1, 
            admin                          : @0x9563578937da5bd33657306871057dbe50c18900d300ecd97c93c3cbda2262ed, 
            platform_fee                   : 5000, 
            graduated_fee                  : 300_000_000_000, 
            initial_virtual_sui_reserves   : 3_000_000_000_000, 
            initial_virtual_token_reserves : 10_000_000_000_000_000, 
            remain_token_reserves          : 2_000_000_000_000_000,
            token_decimals                 : 6,
            protocol_vault                 : balance::zero(),
            fair_launch_sui_amount         : 6_000_000_000_000,
        };
        let admin_cap_id = object::id(&admin_cap);
        let config_id = object::id(&config);
        transfer::public_transfer(admin_cap, tx_context::sender(txContext));
        transfer::public_share_object<Configuration>(config);

        event::emit(InitConfigEvent {
            admin_cap_id,
            config_id,
        });
    }

        
    public entry fun migrate_version(
        _admin_cap: &AdminCap, 
        config: &mut Configuration,
        new_version: u64
    ) {
        let old_version = config.version;
        assert!(new_version > old_version, EWrongVersion);
        config.version = new_version;
        event::emit(SetPackageVersion { new_version, old_version });
    }

    fun check_version(version: u64) {
        assert!(version == CURRENT_VERSION, EWrongVersion);
    }


    fun swap<T>(
        pool: &mut Pool<T>, 
        tokenCoin: Coin<T>, 
        suiCoin: Coin<SUI>, 
        tokenAmount: u64, 
        suiAmount: u64, 
        txContext: &mut tx_context::TxContext
    ) : (Coin<T>, Coin<SUI>) {
        assert!(coin::value<T>(&tokenCoin) > 0 || coin::value<SUI>(&suiCoin) > 0, EIncorrectCoinAmount);
        if (coin::value<T>(&tokenCoin) > 0) {
            pool.virtual_token_reserves = pool.virtual_token_reserves - tokenAmount;
        };
        if (coin::value<SUI>(&suiCoin) > 0) {
            pool.virtual_sui_reserves = pool.virtual_sui_reserves - suiAmount;
        };
        let virtual_token_reserves_last = pool.virtual_token_reserves;
        let virtual_sui_reserves_last = pool.virtual_sui_reserves;
        pool.virtual_token_reserves = pool.virtual_token_reserves + coin::value<T>(&tokenCoin);
        pool.virtual_sui_reserves = pool.virtual_sui_reserves + coin::value<SUI>(&suiCoin);
        check_lp_value_is_increased_or_not_changed(
            virtual_token_reserves_last, 
            virtual_sui_reserves_last, 
            pool.virtual_token_reserves, 
            pool.virtual_sui_reserves
        );
        balance::join<T>(&mut pool.real_token_reserves, coin::into_balance(tokenCoin));
        balance::join<SUI>(&mut pool.real_sui_reserves, coin::into_balance(suiCoin));
        assert!(balance::value(&pool.real_token_reserves) >= tokenAmount, ETokenReservesNotEnough);
        assert!(balance::value(&pool.real_sui_reserves) >= suiAmount, ESuiReservesNotEnough);
        (
            coin::from_balance(balance::split<T>(&mut pool.real_token_reserves, tokenAmount), txContext), 
            coin::from_balance(balance::split<SUI>(&mut pool.real_sui_reserves, suiAmount), txContext)
        )
    }

    public entry fun buy<T>(
        config: &mut Configuration,
        paymentCoin: Coin<SUI>,
        amount: u64,
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock,
        txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);
        let sender = tx_context::sender(txContext);
        let (remainingSuiCoin, boughtTokenCoin) = buy_with_return(
            config,
            paymentCoin,
            amount,
            amount_threshold,
            is_exact_in,
            clock,
            txContext
        );
        transfer::public_transfer<Coin<SUI>>(remainingSuiCoin, sender);
        transfer::public_transfer<Coin<T>>(boughtTokenCoin, sender);
    }

    public fun buy_with_return<T>(
        config: &mut Configuration,
        mut paymentCoin: Coin<SUI>,
        amount: u64,
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock,
        txContext: &mut tx_context::TxContext
    ): (Coin<SUI>, Coin<T>) {
        check_version(config.version);

        let sender = tx_context::sender(txContext);
        let typeName = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id,
            type_name::get_address(&typeName)
        );
        assert!(!pool.is_completed, EPoolNotCompleted);
        assert!(amount > 0, EIncorrectCoinAmount);
        let paymentCoinValue = coin::value<SUI>(&paymentCoin);
        let availableTokenAmount = pool.virtual_token_reserves - balance::value<T>(&pool.remain_token_reserves);
        let platformFee;
        let platformFeeSuiCoin;
        let tokenAmountToBuy;
        let suiCost;
        if (is_exact_in) {
            platformFee = full_math_u64::mul_div_ceil(amount, config.platform_fee, FEE_RATE_SCALE);
            suiCost = amount - platformFee;
            tokenAmountToBuy = curves::calculate_token_return(
                suiCost,
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
            );
            assert(tokenAmountToBuy >= amount_threshold, EAmountOutBelowMinimum);
        } else {
            tokenAmountToBuy = std::u64::min(amount, availableTokenAmount);
            suiCost = curves::calculate_liquidity_cost(
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
                tokenAmountToBuy
            );
            platformFee = full_math_u64::mul_div_ceil(suiCost, config.platform_fee, FEE_RATE_SCALE);
            assert(suiCost <= amount_threshold, EAmountInAboveMaximum);
        };
        assert!(paymentCoinValue >= suiCost + platformFee, ESuiAmountNotEnough);
        let platformFeeSuiCoin = coin::split<SUI>(&mut paymentCoin, platformFee, txContext);
        balance::join(&mut config.protocol_vault, coin::into_balance(platformFeeSuiCoin));
        let (boughtTokenCoin, remainingSuiCoin) = swap<T>(
            pool,
            coin::zero<T>(txContext),
            paymentCoin,
            tokenAmountToBuy,
            paymentCoinValue - suiCost - platformFee,
            txContext
        );

        pool.virtual_token_reserves = pool.virtual_token_reserves - coin::value<T>(&boughtTokenCoin);
        if (availableTokenAmount == tokenAmountToBuy || balance::value<SUI>(&pool.real_sui_reserves) >= config.fair_launch_sui_amount) {
            let admin = config.admin;
            let graduated_fee = config.graduated_fee;
            transfer_pool<T>(pool, admin, graduated_fee, clock, txContext);
        };
        let tradedEvent = TradedEvent{
            is_buy: true,
            user: sender,
            token_address: type_name::into_string(typeName),
            sui_amount: suiCost,
            token_amount: tokenAmountToBuy,
            fee_amount: platformFee,
            real_sui_reserves: balance::value(&pool.real_sui_reserves),
            real_token_reserves: balance::value(&pool.real_token_reserves),
            virtual_sui_reserves: pool.virtual_sui_reserves,
            virtual_token_reserves: pool.virtual_token_reserves,
            remain_token_reserves: balance::value(&pool.remain_token_reserves),
            is_completed: pool.is_completed,
            pool_id: object::id<Pool<T>>(pool),
        };
        event::emit<TradedEvent>(tradedEvent);

        (
            remainingSuiCoin,
            boughtTokenCoin
        )
    }
    
    public fun create<T>(
        config: &mut Configuration, 
        mut treasuryCap:coin::TreasuryCap<T>,
        paymentCoin: Coin<SUI>,
        name: ascii::String, 
        symbol: ascii::String, 
        uri: ascii::String, 
        description: ascii::String, 
        twitter: ascii::String, 
        telegram: ascii::String, 
        website: ascii::String, 
        _clock: &clock::Clock, 
        txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        // Validate the lengths of the string parameters
        assert!(ascii::length(&uri) <= 300, EInvalidCreateParams);
        assert!(ascii::length(&description) <= 1000, EInvalidCreateParams);
        assert!(ascii::length(&twitter) <= 500, EInvalidCreateParams);
        assert!(ascii::length(&telegram) <= 500, EInvalidCreateParams);
        assert!(ascii::length(&website) <= 500, EInvalidCreateParams);
        
        // Ensure the total supply of the token is zero
        assert!(coin::total_supply<T>(&treasuryCap) == 0, EInvalidCoinTreasuryCap);
        
        // Create a new Pool object with initial configurations
        let newPool = Pool<T> {
            id: object::new(txContext), 
            real_sui_reserves: balance::zero<SUI>(), 
            real_token_reserves: coin::into_balance(coin::mint<T>(
                &mut treasuryCap, 
                config.initial_virtual_token_reserves - config.remain_token_reserves, 
                txContext
            )), 
            virtual_token_reserves: config.initial_virtual_token_reserves, 
            virtual_sui_reserves: config.initial_virtual_sui_reserves, 
            remain_token_reserves: coin::into_balance(coin::mint<T>(
                &mut treasuryCap, 
                config.remain_token_reserves, 
                txContext
            )), 
            is_completed: false,
        };
        let new_pool_id = object::id<Pool<T>>(&newPool);
        
        // Retrieve the type name for the token T
        let tokenTypeName = type_name::get<T>();
        
        
        // Get the type name for the Pool object
        let poolTypeName = type_name::get<Pool<T>>();

           
        // Transfer the treasury cap to a designated address (null address in this case)
        transfer::public_transfer<coin::TreasuryCap<T>>(treasuryCap, @0x0);

        let deploymentFee = coin::value(&paymentCoin);
        
        balance::join(&mut config.protocol_vault, coin::into_balance(paymentCoin));

        // Create a CreatedEvent to log the creation of the pool
        let createdEvent = CreatedEvent {
            name: name, 
            symbol: symbol, 
            uri: uri, 
            description: description, 
            twitter: twitter, 
            telegram: telegram, 
            website: website, 
            token_address: type_name::into_string(tokenTypeName), 
            bonding_curve: type_name::get_module(&poolTypeName), 
            pool_id: new_pool_id, 
            created_by: tx_context::sender(txContext), 
            real_sui_reserves: 0,
            real_token_reserves: balance::value(&newPool.real_token_reserves),
            virtual_sui_reserves: config.initial_virtual_sui_reserves, 
            virtual_token_reserves: config.initial_virtual_token_reserves, 
            remain_token_reserves: config.remain_token_reserves,
            is_completed: false,
            deployment_fee: deploymentFee,
        };

        // Add the new Pool object to the dynamic object field using its address as a key
        dynamic_object_field::add<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&tokenTypeName), 
            newPool
        );
        
        // Emit the created event
        event::emit<CreatedEvent>(createdEvent);
    }

    public entry fun sell<T>(
        config: &mut Configuration, 
        tokenCoin: Coin<T>, 
        amount: u64, 
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock, 
        txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);
        let sender = tx_context::sender(txContext);
        let (suiCoinReturned, remainingTokenCoin) = sell_with_return(
            config,
            tokenCoin,
            amount,
            amount_threshold,
            is_exact_in,
            clock,
            txContext
        );
        transfer::public_transfer<Coin<T>>(remainingTokenCoin, sender);
        transfer::public_transfer<Coin<SUI>>(suiCoinReturned, sender);
    }
    
    public fun sell_with_return<T>(
        config: &mut Configuration, 
        tokenCoin: Coin<T>, 
        amount: u64, 
        amount_threshold: u64,
        is_exact_in: bool,
        _clock: &clock::Clock, 
        txContext: &mut tx_context::TxContext
    ): (Coin<SUI>, Coin<T>) {
        check_version(config.version);

        let tokenTypeName = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&tokenTypeName)
        );
        
        assert!(!pool.is_completed, EPoolNotCompleted);
        let tokenValue = coin::value<T>(&tokenCoin);
        assert!(tokenValue > 0, EIncorrectCoinAmount);

        let tokenAmountToSell;
        let platformFee;
        let suiReceived;
        if (is_exact_in) {
            tokenAmountToSell = amount;
            suiReceived = curves::calculate_sui_return(
                tokenAmountToSell,
                pool.virtual_sui_reserves, 
                pool.virtual_token_reserves,
            );
            platformFee = full_math_u64::mul_div_ceil(suiReceived, config.platform_fee, FEE_RATE_SCALE);
            assert!(suiReceived - platformFee >= amount_threshold, EAmountOutBelowMinimum);
        } else {
            platformFee = full_math_u64::mul_div_ceil(amount, config.platform_fee, FEE_RATE_SCALE);
            suiReceived = amount + platformFee;
            tokenAmountToSell = curves::calculate_token_return(
                suiReceived,
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
            );
            assert(tokenAmountToSell < amount_threshold, EAmountInAboveMaximum);

        };
        
        let (remainingTokenCoin,mut suiCoinReturned) = swap<T>(
            pool, 
            tokenCoin,
            coin::zero<SUI>(txContext), 
            tokenValue - tokenAmountToSell, 
            suiReceived, 
            txContext
        );
        pool.virtual_sui_reserves = pool.virtual_sui_reserves - coin::value<SUI>(&suiCoinReturned);
        balance::join(&mut config.protocol_vault, coin::into_balance(coin::split<SUI>(&mut suiCoinReturned, platformFee, txContext)));
        
        let tradeEvent = TradedEvent {
            is_buy: false, 
            user: tx_context::sender(txContext), 
            token_address: type_name::into_string(tokenTypeName), 
            sui_amount: suiReceived, 
            token_amount: tokenValue, 
            fee_amount: platformFee,
            real_sui_reserves: balance::value(&pool.real_sui_reserves),
            real_token_reserves: balance::value(&pool.real_token_reserves),
            virtual_sui_reserves: pool.virtual_sui_reserves, 
            virtual_token_reserves: pool.virtual_token_reserves, 
            remain_token_reserves: balance::value(&pool.remain_token_reserves),
            is_completed: pool.is_completed,
            pool_id: object::id<Pool<T>>(pool), 
        };
        
        event::emit<TradedEvent>(tradeEvent);
        
        (suiCoinReturned, remainingTokenCoin)
    }

    fun check_lp_value_is_increased_or_not_changed(
        virtual_token_reserves_last: u64, 
        virtual_sui_reserves_last: u64, 
        virtual_token_reserves: u64, 
        virtual_sui_reserves: u64
    ) {
        assert!((virtual_token_reserves_last as u128) * (virtual_sui_reserves_last as u128) <= (virtual_token_reserves as u128) * (virtual_sui_reserves as u128), EIncorrectLP);
    }
    
    fun transfer_pool<T>(
        pool: &mut Pool<T>,
        recipient: address, 
        _graduatedFee: u64, 
        _clock: &clock::Clock, 
        txContext: &mut tx_context::TxContext
    ) {
        pool.is_completed = true;

        let real_token_reserves_amount = balance::value<T>(&pool.real_token_reserves);
        let mut combinedTokenReserves = balance::split<T>(
            &mut pool.real_token_reserves, 
            real_token_reserves_amount, 
        );

        let remain_token_reserves_amount = balance::value<T>(&pool.remain_token_reserves);
        balance::join<T>(
            &mut combinedTokenReserves, 
            balance::split<T>(
                &mut pool.remain_token_reserves, 
                remain_token_reserves_amount,
            )
        );

        let real_sui_reserves_amount = balance::value<SUI>(&pool.real_sui_reserves);
        transfer::public_transfer<Coin<SUI>>(
            coin::from_balance(balance::split<SUI>(
                &mut pool.real_sui_reserves, 
                real_sui_reserves_amount, 
            ), txContext), 
            recipient,
        );

        transfer::public_transfer<Coin<T>>(
            coin::from_balance(combinedTokenReserves, txContext), 
            recipient,
        );

        let poolCompletedEvent = PoolCompletedEvent {
            token_address: type_name::into_string(type_name::get<T>()), 
            lp: ascii::string(b"0x0"),
        };

        event::emit<PoolCompletedEvent>(poolCompletedEvent);
    }

    public entry fun update_config(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        newPlatformFee: u64, 
        newGraduatedFee: u64, 
        newInitialVirtualSuiReserves: u64, 
        newInitialVirtualTokenReserves: u64, 
        newRemainTokenReserves: u64, 
        newTokenDecimals: u8,
        newFairLaunchSuiAmount: u64,
        _clock: &clock::Clock, 
        _txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        config.platform_fee = newPlatformFee;
        config.graduated_fee = newGraduatedFee;
        config.initial_virtual_sui_reserves = newInitialVirtualSuiReserves;
        config.initial_virtual_token_reserves = newInitialVirtualTokenReserves;
        config.remain_token_reserves = newRemainTokenReserves;
        config.token_decimals = newTokenDecimals;
        config.fair_launch_sui_amount = newFairLaunchSuiAmount;

        let configChangedEvent = ConfigChangedEvent {
            platform_fee: newPlatformFee,
            graduated_fee: newGraduatedFee,
            initial_virtual_sui_reserves: newInitialVirtualSuiReserves,
            initial_virtual_token_reserves: newInitialVirtualTokenReserves,
            remain_token_reserves: newRemainTokenReserves,
            token_decimals: newTokenDecimals,
            fair_launch_sui_amount: newFairLaunchSuiAmount,
        };

        event::emit<ConfigChangedEvent>(configChangedEvent);
    }

    public entry fun transfer_admin(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        new_admin: address,
        _txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        let old_admin = config.admin;
        config.admin = new_admin;

        event::emit(OwnershipTransferredEvent{
            old_admin, 
            new_admin, 
        });
    }

    public entry fun collect_protocol_fee(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        amount_requested: u64,
        recipient: address,
        txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        let pool_amount = balance::value(&config.protocol_vault);
        let amount = if (amount_requested > pool_amount) pool_amount else amount_requested;
        let return_fee = coin::from_balance(balance::split(&mut config.protocol_vault, amount), txContext);

        transfer::public_transfer(return_fee, recipient);
    }

    public entry fun skim<T>(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        txContext: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        let tokenTypeName = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&tokenTypeName)
        );
        
        assert!(pool.is_completed, EPoolNotCompleted);
        
        let real_sui_reserves_amount = balance::value<SUI>(&pool.real_sui_reserves);
        let real_token_reserves_amount = balance::value<T>(&pool.real_token_reserves);
        transfer::public_transfer<coin::Coin<SUI>>(
            coin::from_balance(
                balance::split<SUI>(
                    &mut pool.real_sui_reserves, 
                    real_sui_reserves_amount, 
                ), 
                txContext
            ),
            config.admin
        );
        
        transfer::public_transfer<coin::Coin<T>>(
            coin::from_balance(
                balance::split<T>(
                    &mut pool.real_token_reserves, 
                    real_token_reserves_amount, 
                ), 
                txContext
            ),
            config.admin
        );
    }

}
