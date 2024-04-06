// This is a template strategy contract for building strategies on Haiko. All Haiko strategies
// must implement a minimal `IStrategy` interface, which contains functions for querying 
// placed and queued strategy positions, and for updating positions before swaps. All other
// functions are optional and can be implemented as needed in a seperate strategy-specific
// interface.

// This template contract also implements the following features for illustration:
// * Contract ownership
// * Deposits and withdrawals for multiple LPs
// * Withdraw fees

// Of course, you are free to add or remove any of these features as needed.

// All strategy contracts should mirror the core `MarketManager` AMM contract in its singleton
// design. This allows a single Strategy contract to deploy strategy vaults and reuse common logic
// across markets. In practice, this means that most functions will take a `market_id` argument.
// This is the same `market_id` used in the `MarketManager` contract, and can also be computed
// from the haiko_lib::id library.

#[starknet::contract]
pub mod TemplateStrategy {
    // Core lib imports.
    use starknet::ContractAddress;
    use starknet::{
        get_caller_address, get_contract_address, get_block_number, get_block_timestamp
    };
    use starknet::class_hash::ClassHash;

    // Local imports.
    use haiko_strategy_template::interface::ITemplateStrategy;

    // Haiko imports.
    use haiko_lib::types::core::{PositionInfo, SwapParams};
    use haiko_lib::math::{price_math, fee_math};
    use haiko_lib::interfaces::IMarketManager::{
        IMarketManagerDispatcher, IMarketManagerDispatcherTrait
    };
    use haiko_lib::interfaces::IStrategy::IStrategy;

    // External imports.
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ///////////////////////////////

    #[storage]
    struct Storage {
        // contract owner
        owner: ContractAddress,
        // strategy name
        name: felt252,
        // strategy symbol
        symbol: felt252,
        // strategy version
        version: felt252,
        // market manager
        market_manager: IMarketManagerDispatcher,
        // placed position by market
        placed_position: LegacyMap::<felt252, PositionInfo>,
        // user share of a market, indexed by (market_id: felt252, user: ContractAddress)
        user_shares: LegacyMap::<(felt252, ContractAddress), u256>,
        // total shares of a market, indexed by market id
        total_shares: LegacyMap::<felt252, u256>,
        // withdraw fee rate, indexed by market_id
        withdraw_fee_rate: LegacyMap::<felt252, u16>,
        // accrued withdraw fee balance, indexed by asset
        withdraw_fees: LegacyMap::<ContractAddress, u256>,
    }

    ////////////////////////////////
    // EVENTS
    ///////////////////////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AddMarket: AddMarket,
        Deposit: Deposit,
        Withdraw: Withdraw,
        UpdatePositions: UpdatePositions,
        CollectWithdrawFee: CollectWithdrawFee,
        SetWithdrawFee: SetWithdrawFee,
        ChangeOwner: ChangeOwner,
    }

    #[derive(Drop, starknet::Event)]
    struct AddMarket {
        #[key]
        market_id: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        caller: ContractAddress,
        #[key]
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        caller: ContractAddress,
        #[key]
        market_id: felt252,
        base_amount: u256,
        quote_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct UpdatePositions {
        #[key]
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct SetWithdrawFee {
        #[key]
        market_id: felt252,
        fee_rate: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct CollectWithdrawFee {
        #[key]
        receiver: ContractAddress,
        #[key]
        token: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ChangeOwner {
        old: ContractAddress,
        new: ContractAddress
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        version: felt252,
        market_manager: ContractAddress,
    ) {
        self.owner.write(owner);
        self.name.write(name);
        self.symbol.write(symbol);
        self.version.write(version);
        let manager_dispatcher = IMarketManagerDispatcher { contract_address: market_manager };
        self.market_manager.write(manager_dispatcher);
    }

    ////////////////////////////////
    // FUNCTIONS
    ////////////////////////////////

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner');
        }
    }

    #[abi(embed_v0)]
    impl Strategy of IStrategy<ContractState> {
        // Get market manager contract address.
        fn market_manager(self: @ContractState) -> ContractAddress {
            self.market_manager.read().contract_address
        }

        // Get strategy name.
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        // Get strategy symbol.
        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        // Get strategy version.
        fn version(self: @ContractState) -> felt252 {
            self.version.read()
        }

        /// Get a list of positions placed by the strategy on the market.
        /// 
        /// # Arguments
        /// * `market_id` - market id
        //
        /// # Returns
        /// * `positions` - list of positions placed by the strategy in the market
        fn placed_positions(self: @ContractState, market_id: felt252) -> Span<PositionInfo> {
            let position = self.placed_position.read(market_id);
            array![position].span()
        }

        /// Get list of positions queued to be placed by strategy on next `swap` update. If no updates
        /// are queued, the returned list will match the list returned by `placed_positions`.
        /// 
        /// # Arguments
        /// * `market_id` - market id
        //
        /// # Returns
        /// * `positions` - list of positions queued to be placed by the strategy on next update
        fn queued_positions(self: @ContractState, market_id: felt252) -> Span<PositionInfo> {
            // TODO ...
            // Here, implement logic for computing next set of position updates ... 

            // Return list of positions.
            array![].span() // TODO: populate with actual position
        }

        /// Called by `MarketManager` before swap to replace `placed_positions` with `queued_positions`.
        /// If the two lists are equal, no positions will be updated.
        /// 
        /// # Arguments
        /// * `market_id` - market id
        /// * `params` - information about the incoming swap
        fn update_positions(ref self: ContractState, market_id: felt252, params: SwapParams) {
            // Run checks
            let market_manager = self.market_manager.read();
            assert(get_caller_address() == market_manager.contract_address, 'OnlyMarketManager');

            let queued_position = *self.queued_positions(market_id).at(0);
            let placed_position = self.placed_position.read(market_id);
            if queued_position != placed_position {
                // TODO: implement logic for updating positions ... 
            }
        }
    }

    #[abi(embed_v0)]
    impl TemplateStrategy of ITemplateStrategy<ContractState> {
        // Contract owner
        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        // User's deposited shares in a given market
        fn user_shares(self: @ContractState, market_id: felt252, owner: ContractAddress) -> u256 {
            self.user_shares.read((market_id, owner))
        }

        // Total deposited shares for a given market
        fn total_shares(self: @ContractState, market_id: felt252) -> u256 {
            self.total_shares.read(market_id)
        }

        // Withdraw fee rate for a given market
        fn withdraw_fee_rate(self: @ContractState, market_id: felt252) -> u16 {
            self.withdraw_fee_rate.read(market_id)
        }

        // Accumulated withdraw fee balance for a given asset
        fn withdraw_fees(self: @ContractState, token: ContractAddress) -> u256 {
            self.withdraw_fees.read(token)
        }

        // Initialise strategy for market.
        //
        // # Arguments
        // * `market_id` - market id
        fn add_market(ref self: ContractState, market_id: felt252) {
            self.assert_owner();

            // TODO
            // Here, implement logic for initialising strategy for market ...

            // Emit events.
            self.emit(Event::AddMarket(AddMarket { market_id }));
        }

        // Deposit initial liquidity to strategy and place positions.
        // Should be used whenever total deposits in a strategy are zero.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset to deposit
        // * `quote_amount` - quote asset to deposit
        //
        // # Returns
        // * `shares` - pool shares minted in the form of liquidity
        fn deposit_initial(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> u256 {
            // Run checks
            assert(base_amount != 0 && quote_amount != 0, 'AmountZero');
            assert(self.total_shares.read(market_id) == 0, 'UseDeposit');

            // TODO: implement logic for calculating user shares
            let shares: u256 = 0; // TODO: replace with actual liquidity minted

            // Transfer tokens.
            let caller = get_caller_address();
            let contract = get_contract_address();
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);
            if base_amount != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer_from(caller, contract, base_amount);
            }
            if quote_amount != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer_from(caller, contract, quote_amount);
            }

            // Mint liquidity
            self.user_shares.write((market_id, caller), shares);
            self.total_shares.write(market_id, shares);

            // Emit event
            self.emit(Event::Deposit(Deposit { market_id, caller, base_amount, quote_amount }));

            shares
        }

        // Deposit liquidity to strategy.
        //
        // # Arguments
        // * `market_id` - market id
        // * `base_amount` - base asset desired
        // * `quote_amount` - quote asset desired
        //
        // # Returns
        // * `base_amount` - base asset deposited
        // * `quote_amount` - quote asset deposited
        // * `shares` - pool shares minted
        fn deposit(
            ref self: ContractState, market_id: felt252, base_amount: u256, quote_amount: u256
        ) -> (u256, u256, u256) {
            // Run checks.
            let total_shares = self.total_shares.read(market_id);
            assert(total_shares != 0, 'UseDepositInitial');
            assert(base_amount != 0 || quote_amount != 0, 'AmountZero');

            // TODO: implement logic for calculating user shares and deposited amounts.
            let shares = 0; // TODO: replace with actual shares minted
            let base_deposit = 0; // TODO: replace with actual base amount deposited
            let quote_deposit = 0; // TODO: replace with actual quote amount deposited

            // Transfer tokens into contract.
            let caller = get_caller_address();
            let contract = get_contract_address();
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);
            if base_deposit != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer_from(caller, contract, base_deposit);
            }
            if quote_deposit != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer_from(caller, contract, quote_deposit);
            }

            // Update deposits.
            let user_shares = self.user_shares.read((market_id, caller));
            self.user_shares.write((market_id, caller), user_shares + shares);
            self.total_shares.write(market_id, total_shares + shares);

            // Emit event.
            self
                .emit(
                    Event::Deposit(
                        Deposit {
                            market_id,
                            caller,
                            base_amount: base_deposit,
                            quote_amount: quote_deposit
                        }
                    )
                );

            (base_deposit, quote_deposit, shares)
        }

        // Burn pool shares and withdraw funds from strategy.
        //
        // # Arguments
        // * `market_id` - market id
        // * `shares` - pool shares to burn
        //
        // # Returns
        // * `base_amount` - base asset withdrawn
        // * `quote_amount` - quote asset withdrawn
        fn withdraw(ref self: ContractState, market_id: felt252, shares: u256) -> (u256, u256) {
            // Run checks
            assert(shares != 0, 'SharesZero');
            let caller = get_caller_address();
            let user_shares = self.user_shares.read((market_id, caller));
            assert(user_shares >= shares, 'InsuffShares');

            // TODO
            // Here, implement logic for calculating withdrawn amounts ... 
            let mut base_withdraw = 0; // TODO: replace with actual base amount withdrawn
            let mut quote_withdraw = 0; // TODO: replace with actual quote amount withdrawn

            // Update shares.
            self.user_shares.write((market_id, caller), user_shares - shares);
            let total_shares = self.total_shares.read(market_id);
            self.total_shares.write(market_id, total_shares - shares);

            // Deduct withdrawal fee.
            let market_manager = self.market_manager.read();
            let market_info = market_manager.market_info(market_id);
            let fee_rate = self.withdraw_fee_rate.read(market_id);
            if fee_rate != 0 {
                let base_fees = fee_math::calc_fee(base_withdraw, fee_rate);
                let quote_fees = fee_math::calc_fee(quote_withdraw, fee_rate);
                base_withdraw -= base_fees;
                quote_withdraw -= quote_fees;

                // Update fee balance.
                if base_fees != 0 {
                    let base_withdraw_fees = self.withdraw_fees.read(market_info.base_token);
                    self
                        .withdraw_fees
                        .write(market_info.base_token, base_withdraw_fees + base_fees);
                }
                if quote_fees != 0 {
                    let quote_withdraw_fees = self.withdraw_fees.read(market_info.quote_token);
                    self
                        .withdraw_fees
                        .write(market_info.quote_token, quote_withdraw_fees + quote_fees);
                }
            }

            // Transfer tokens.
            if base_withdraw != 0 {
                let base_token = IERC20Dispatcher { contract_address: market_info.base_token };
                base_token.transfer(caller, base_withdraw);
            }
            if quote_withdraw != 0 {
                let quote_token = IERC20Dispatcher { contract_address: market_info.quote_token };
                quote_token.transfer(caller, quote_withdraw);
            }

            // Emit event.
            self
                .emit(
                    Event::Withdraw(
                        Withdraw {
                            market_id,
                            caller,
                            base_amount: base_withdraw,
                            quote_amount: quote_withdraw
                        }
                    )
                );

            // Return withdrawn amounts.
            (base_withdraw, quote_withdraw)
        }

        // Collect withdrawal fees.
        // Only callable by contract owner.
        //
        // # Arguments
        // * `receiver` - address to receive fees
        // * `token` - token to collect fees for
        // * `amount` - amount of fees requested
        fn collect_withdraw_fees(
            ref self: ContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
        ) -> u256 {
            // Run checks.
            self.assert_owner();
            let mut fees = self.withdraw_fees.read(token);
            assert(fees >= amount, 'InsuffFees');

            // Update fee balance.
            fees -= amount;
            self.withdraw_fees.write(token, fees);

            // Transfer fees to caller.
            let dispatcher = IERC20Dispatcher { contract_address: token };
            dispatcher.transfer(get_caller_address(), amount);

            // Emit event.
            self.emit(Event::CollectWithdrawFee(CollectWithdrawFee { receiver, token, amount }));

            // Return amount collected.
            amount
        }

        // Set withdraw fee for a given market.
        // Only callable by contract owner.
        //
        // # Arguments
        // * `market_id` - market id
        // * `fee_rate` - fee rate
        fn set_withdraw_fee(ref self: ContractState, market_id: felt252, fee_rate: u16) {
            self.assert_owner();
            let old_fee_rate = self.withdraw_fee_rate.read(market_id);
            assert(old_fee_rate != fee_rate, 'FeeUnchanged');
            assert(fee_rate <= fee_math::MAX_FEE_RATE, 'FeeOF');
            self.withdraw_fee_rate.write(market_id, fee_rate);
            self.emit(Event::SetWithdrawFee(SetWithdrawFee { market_id, fee_rate }));
        }

        // Transfer ownership of the contract.
        //
        // # Arguments
        // * `new_owner` - New owner of the contract
        fn transfer_owner(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_owner();
            let old_owner = self.owner.read();
            assert(new_owner != old_owner, 'SameOwner');
            self.owner.write(new_owner);
            self.emit(Event::ChangeOwner(ChangeOwner { old: old_owner, new: new_owner }));
        }
    }
}
