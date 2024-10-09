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

    fun init(tx_context: &mut tx_context::TxContext) {
        let admin_cap= AdminCap {
            id: object::new(tx_context),
        };
        let config = Configuration{
            id                             : object::new(tx_context), 
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
        transfer::public_transfer(admin_cap, tx_context::sender(tx_context));
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
        token_coin: Coin<T>, 
        sui_coin: Coin<SUI>, 
        token_amount: u64, 
        sui_amount: u64, 
        tx_context: &mut tx_context::TxContext
    ) : (Coin<T>, Coin<SUI>) {
        assert!(coin::value<T>(&token_coin) > 0 || coin::value<SUI>(&sui_coin) > 0, EIncorrectCoinAmount);
        if (coin::value<T>(&token_coin) > 0) {
            pool.virtual_token_reserves = pool.virtual_token_reserves - token_amount;
        };
        if (coin::value<SUI>(&sui_coin) > 0) {
            pool.virtual_sui_reserves = pool.virtual_sui_reserves - sui_amount;
        };
        let virtual_token_reserves_last = pool.virtual_token_reserves;
        let virtual_sui_reserves_last = pool.virtual_sui_reserves;
        pool.virtual_token_reserves = pool.virtual_token_reserves + coin::value<T>(&token_coin);
        pool.virtual_sui_reserves = pool.virtual_sui_reserves + coin::value<SUI>(&sui_coin);
        check_lp_value_is_increased_or_not_changed(
            virtual_token_reserves_last, 
            virtual_sui_reserves_last, 
            pool.virtual_token_reserves, 
            pool.virtual_sui_reserves
        );
        balance::join<T>(&mut pool.real_token_reserves, coin::into_balance(token_coin));
        balance::join<SUI>(&mut pool.real_sui_reserves, coin::into_balance(sui_coin));
        assert!(balance::value(&pool.real_token_reserves) >= token_amount, ETokenReservesNotEnough);
        assert!(balance::value(&pool.real_sui_reserves) >= sui_amount, ESuiReservesNotEnough);
        (
            coin::from_balance(balance::split<T>(&mut pool.real_token_reserves, token_amount), tx_context), 
            coin::from_balance(balance::split<SUI>(&mut pool.real_sui_reserves, sui_amount), tx_context)
        )
    }

    public entry fun buy<T>(
        config: &mut Configuration,
        payment_coin: Coin<SUI>,
        amount: u64,
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock,
        tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);
        let sender = tx_context::sender(tx_context);
        let (remaining_sui_coin, bought_token_coin) = buy_with_return(
            config,
            payment_coin,
            amount,
            amount_threshold,
            is_exact_in,
            clock,
            tx_context
        );
        transfer::public_transfer<Coin<SUI>>(remaining_sui_coin, sender);
        transfer::public_transfer<Coin<T>>(bought_token_coin, sender);
    }

    public fun buy_with_return<T>(
        config: &mut Configuration,
        mut payment_coin: Coin<SUI>,
        amount: u64,
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock,
        tx_context: &mut tx_context::TxContext
    ): (Coin<SUI>, Coin<T>) {
        check_version(config.version);

        let sender = tx_context::sender(tx_context);
        let type_name = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id,
            type_name::get_address(&type_name)
        );
        assert!(!pool.is_completed, EPoolNotCompleted);
        assert!(amount > 0, EIncorrectCoinAmount);
        let payment_coinValue = coin::value<SUI>(&payment_coin);
        let available_token_amount = pool.virtual_token_reserves - balance::value<T>(&pool.remain_token_reserves);
        let platform_fee;
        let token_amount_to_buy;
        let suiCost;
        if (is_exact_in) {
            platform_fee = full_math_u64::mul_div_ceil(amount, config.platform_fee, FEE_RATE_SCALE);
            suiCost = amount - platform_fee;
            token_amount_to_buy = curves::calculate_token_return(
                suiCost,
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
            );
            assert!(token_amount_to_buy >= amount_threshold, EAmountOutBelowMinimum);
        } else {
            token_amount_to_buy = std::u64::min(amount, available_token_amount);
            suiCost = curves::calculate_liquidity_cost(
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
                token_amount_to_buy
            );
            platform_fee = full_math_u64::mul_div_ceil(suiCost, config.platform_fee, FEE_RATE_SCALE);
            assert!(suiCost <= amount_threshold, EAmountInAboveMaximum);
        };
        assert!(payment_coinValue >= suiCost + platform_fee, ESuiAmountNotEnough);
        let platform_fee_sui_coin = coin::split<SUI>(&mut payment_coin, platform_fee, tx_context);
        balance::join(&mut config.protocol_vault, coin::into_balance(platform_fee_sui_coin));
        let (bought_token_coin, remaining_sui_coin) = swap<T>(
            pool,
            coin::zero<T>(tx_context),
            payment_coin,
            token_amount_to_buy,
            payment_coinValue - suiCost - platform_fee,
            tx_context
        );

        pool.virtual_token_reserves = pool.virtual_token_reserves - coin::value<T>(&bought_token_coin);
        if (available_token_amount == token_amount_to_buy || balance::value<SUI>(&pool.real_sui_reserves) >= config.fair_launch_sui_amount) {
            let admin = config.admin;
            let graduated_fee = config.graduated_fee;
            transfer_pool<T>(pool, admin, graduated_fee, clock, tx_context);
        };
        let tradedEvent = TradedEvent{
            is_buy: true,
            user: sender,
            token_address: type_name::into_string(type_name),
            sui_amount: suiCost,
            token_amount: token_amount_to_buy,
            fee_amount: platform_fee,
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
            remaining_sui_coin,
            bought_token_coin
        )
    }
    
    public fun create<T>(
        config: &mut Configuration, 
        mut treasury_cap:coin::TreasuryCap<T>,
        payment_coin: Coin<SUI>,
        name: ascii::String, 
        symbol: ascii::String, 
        uri: ascii::String, 
        description: ascii::String, 
        twitter: ascii::String, 
        telegram: ascii::String, 
        website: ascii::String, 
        _clock: &clock::Clock, 
        tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        // Validate the lengths of the string parameters
        assert!(ascii::length(&uri) <= 300, EInvalidCreateParams);
        assert!(ascii::length(&description) <= 1000, EInvalidCreateParams);
        assert!(ascii::length(&twitter) <= 500, EInvalidCreateParams);
        assert!(ascii::length(&telegram) <= 500, EInvalidCreateParams);
        assert!(ascii::length(&website) <= 500, EInvalidCreateParams);
        
        // Ensure the total supply of the token is zero
        assert!(coin::total_supply<T>(&treasury_cap) == 0, EInvalidCoinTreasuryCap);
        
        // Create a new Pool object with initial configurations
        let new_pool = Pool<T> {
            id: object::new(tx_context), 
            real_sui_reserves: balance::zero<SUI>(), 
            real_token_reserves: coin::into_balance(coin::mint<T>(
                &mut treasury_cap, 
                config.initial_virtual_token_reserves - config.remain_token_reserves, 
                tx_context
            )), 
            virtual_token_reserves: config.initial_virtual_token_reserves, 
            virtual_sui_reserves: config.initial_virtual_sui_reserves, 
            remain_token_reserves: coin::into_balance(coin::mint<T>(
                &mut treasury_cap, 
                config.remain_token_reserves, 
                tx_context
            )), 
            is_completed: false,
        };
        let new_pool_id = object::id<Pool<T>>(&new_pool);
        
        // Retrieve the type name for the token T
        let token_type_name = type_name::get<T>();
        
        
        // Get the type name for the Pool object
        let pool_type_name = type_name::get<Pool<T>>();

           
        // Transfer the treasury cap to a designated address (null address in this case)
        transfer::public_transfer<coin::TreasuryCap<T>>(treasury_cap, @0x0);

        let deployment_fee = coin::value(&payment_coin);
        
        balance::join(&mut config.protocol_vault, coin::into_balance(payment_coin));

        // Create a CreatedEvent to log the creation of the pool
        let created_event = CreatedEvent {
            name: name, 
            symbol: symbol, 
            uri: uri, 
            description: description, 
            twitter: twitter, 
            telegram: telegram, 
            website: website, 
            token_address: type_name::into_string(token_type_name), 
            bonding_curve: type_name::get_module(&pool_type_name), 
            pool_id: new_pool_id, 
            created_by: tx_context::sender(tx_context), 
            real_sui_reserves: 0,
            real_token_reserves: balance::value(&new_pool.real_token_reserves),
            virtual_sui_reserves: config.initial_virtual_sui_reserves, 
            virtual_token_reserves: config.initial_virtual_token_reserves, 
            remain_token_reserves: config.remain_token_reserves,
            is_completed: false,
            deployment_fee: deployment_fee,
        };

        // Add the new Pool object to the dynamic object field using its address as a key
        dynamic_object_field::add<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&token_type_name), 
            new_pool
        );
        
        // Emit the created event
        event::emit<CreatedEvent>(created_event);
    }

    public entry fun sell<T>(
        config: &mut Configuration, 
        token_coin: Coin<T>, 
        amount: u64, 
        amount_threshold: u64,
        is_exact_in: bool,
        clock: &clock::Clock, 
        tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);
        let sender = tx_context::sender(tx_context);
        let (sui_coin_returned, remaining_token_coin) = sell_with_return(
            config,
            token_coin,
            amount,
            amount_threshold,
            is_exact_in,
            clock,
            tx_context
        );
        transfer::public_transfer<Coin<T>>(remaining_token_coin, sender);
        transfer::public_transfer<Coin<SUI>>(sui_coin_returned, sender);
    }
    
    public fun sell_with_return<T>(
        config: &mut Configuration, 
        token_coin: Coin<T>, 
        amount: u64, 
        amount_threshold: u64,
        is_exact_in: bool,
        _clock: &clock::Clock, 
        tx_context: &mut tx_context::TxContext
    ): (Coin<SUI>, Coin<T>) {
        check_version(config.version);

        let token_type_name = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&token_type_name)
        );
        
        assert!(!pool.is_completed, EPoolNotCompleted);
        let tokenValue = coin::value<T>(&token_coin);
        assert!(tokenValue > 0, EIncorrectCoinAmount);

        let token_amount_to_sell;
        let platform_fee;
        let sui_received;
        if (is_exact_in) {
            token_amount_to_sell = amount;
            sui_received = curves::calculate_sui_return(
                token_amount_to_sell,
                pool.virtual_sui_reserves, 
                pool.virtual_token_reserves,
            );
            platform_fee = full_math_u64::mul_div_ceil(sui_received, config.platform_fee, FEE_RATE_SCALE);
            assert!(sui_received - platform_fee >= amount_threshold, EAmountOutBelowMinimum);
        } else {
            platform_fee = full_math_u64::mul_div_ceil(amount, config.platform_fee, FEE_RATE_SCALE);
            sui_received = amount + platform_fee;
            token_amount_to_sell = curves::calculate_token_return(
                sui_received,
                pool.virtual_sui_reserves,
                pool.virtual_token_reserves,
            );
            assert!(token_amount_to_sell < amount_threshold, EAmountInAboveMaximum);

        };
        
        let (remaining_token_coin,mut sui_coin_returned) = swap<T>(
            pool, 
            token_coin,
            coin::zero<SUI>(tx_context), 
            tokenValue - token_amount_to_sell, 
            sui_received, 
            tx_context
        );
        pool.virtual_sui_reserves = pool.virtual_sui_reserves - coin::value<SUI>(&sui_coin_returned);
        balance::join(&mut config.protocol_vault, coin::into_balance(coin::split<SUI>(&mut sui_coin_returned, platform_fee, tx_context)));
        
        let trade_event = TradedEvent {
            is_buy: false, 
            user: tx_context::sender(tx_context), 
            token_address: type_name::into_string(token_type_name), 
            sui_amount: sui_received, 
            token_amount: tokenValue, 
            fee_amount: platform_fee,
            real_sui_reserves: balance::value(&pool.real_sui_reserves),
            real_token_reserves: balance::value(&pool.real_token_reserves),
            virtual_sui_reserves: pool.virtual_sui_reserves, 
            virtual_token_reserves: pool.virtual_token_reserves, 
            remain_token_reserves: balance::value(&pool.remain_token_reserves),
            is_completed: pool.is_completed,
            pool_id: object::id<Pool<T>>(pool), 
        };
        
        event::emit<TradedEvent>(trade_event);
        
        (sui_coin_returned, remaining_token_coin)
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
        _graduated_fee: u64, 
        _clock: &clock::Clock, 
        tx_context: &mut tx_context::TxContext
    ) {
        pool.is_completed = true;

        let real_token_reserves_amount = balance::value<T>(&pool.real_token_reserves);
        let mut combined_token_teserves = balance::split<T>(
            &mut pool.real_token_reserves, 
            real_token_reserves_amount, 
        );

        let remain_token_reserves_amount = balance::value<T>(&pool.remain_token_reserves);
        balance::join<T>(
            &mut combined_token_teserves, 
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
            ), tx_context), 
            recipient,
        );

        transfer::public_transfer<Coin<T>>(
            coin::from_balance(combined_token_teserves, tx_context), 
            recipient,
        );

        let pool_completed_event = PoolCompletedEvent {
            token_address: type_name::into_string(type_name::get<T>()), 
            lp: ascii::string(b"0x0"),
        };

        event::emit<PoolCompletedEvent>(pool_completed_event);
    }

    public entry fun update_config(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        new_platform_fee: u64, 
        new_graduated_fee: u64, 
        new_initial_virtual_sui_reserves: u64, 
        new_initial_virtual_token_reserves: u64, 
        new_remain_token_reserves: u64, 
        new_token_decimals: u8,
        new_fair_launch_sui_amount: u64,
        _clock: &clock::Clock, 
        _tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        config.platform_fee = new_platform_fee;
        config.graduated_fee = new_graduated_fee;
        config.initial_virtual_sui_reserves = new_initial_virtual_sui_reserves;
        config.initial_virtual_token_reserves = new_initial_virtual_token_reserves;
        config.remain_token_reserves = new_remain_token_reserves;
        config.token_decimals = new_token_decimals;
        config.fair_launch_sui_amount = new_fair_launch_sui_amount;

        let config_changed_event = ConfigChangedEvent {
            platform_fee: new_platform_fee,
            graduated_fee: new_graduated_fee,
            initial_virtual_sui_reserves: new_initial_virtual_sui_reserves,
            initial_virtual_token_reserves: new_initial_virtual_token_reserves,
            remain_token_reserves: new_remain_token_reserves,
            token_decimals: new_token_decimals,
            fair_launch_sui_amount: new_fair_launch_sui_amount,
        };

        event::emit<ConfigChangedEvent>(config_changed_event);
    }

    public entry fun transfer_admin(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        new_admin: address,
        _tx_context: &mut tx_context::TxContext
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
        tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        let pool_amount = balance::value(&config.protocol_vault);
        let amount = if (amount_requested > pool_amount) pool_amount else amount_requested;
        let return_fee = coin::from_balance(balance::split(&mut config.protocol_vault, amount), tx_context);

        transfer::public_transfer(return_fee, recipient);
    }

    public entry fun skim<T>(
        _admin_cap: &AdminCap,
        config: &mut Configuration, 
        tx_context: &mut tx_context::TxContext
    ) {
        check_version(config.version);

        let token_type_name = type_name::get<T>();
        let pool = dynamic_object_field::borrow_mut<ascii::String, Pool<T>>(
            &mut config.id, 
            type_name::get_address(&token_type_name)
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
                tx_context
            ),
            config.admin
        );
        
        transfer::public_transfer<coin::Coin<T>>(
            coin::from_balance(
                balance::split<T>(
                    &mut pool.real_token_reserves, 
                    real_token_reserves_amount, 
                ), 
                tx_context
            ),
            config.admin
        );
    }

}
