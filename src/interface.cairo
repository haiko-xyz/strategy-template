// Core lib imports.
use starknet::ContractAddress;

// Local imports.
use haiko_lib::interfaces::IStrategy::IStrategy;

// All Haiko strategies must implement the minimal `IStrategy` interface importable from the 
// Haiko common library at haiko_lib::interfaces::IStrategy. All other functions can be 
// specified in the strategy-specific interface below.
#[starknet::interface]
pub trait ITemplateStrategy<TContractState> {
    // Contract owner
    fn owner(self: @TContractState) -> ContractAddress;

    // User's deposited shares in a given market
    fn user_shares(self: @TContractState, market_id: felt252, owner: ContractAddress) -> u256;

    // Total deposited shares  in a given market
    fn total_shares(self: @TContractState, market_id: felt252) -> u256;

    // Withdraw fee rate for a given market
    fn withdraw_fee_rate(self: @TContractState, market_id: felt252) -> u16;

    // Accumulated withdraw fee balance for a given asset
    fn withdraw_fees(self: @TContractState, token: ContractAddress) -> u256;
    // Initialise strategy for market.
    //
    // # Arguments
    // * `market_id` - market id
    fn add_market(ref self: TContractState, market_id: felt252);

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
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> u256;

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
        ref self: TContractState, market_id: felt252, base_amount: u256, quote_amount: u256
    ) -> (u256, u256, u256);

    // Burn pool shares and withdraw funds from strategy.
    //
    // # Arguments
    // * `market_id` - market id
    // * `shares` - pool shares to burn
    //
    // # Returns
    // * `base_amount` - base asset withdrawn
    // * `quote_amount` - quote asset withdrawn
    fn withdraw(ref self: TContractState, market_id: felt252, shares: u256) -> (u256, u256);

    // Collect withdrawal fees.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `receiver` - address to receive fees
    // * `token` - token to collect fees for
    // * `amount` - amount of fees requested
    fn collect_withdraw_fees(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256
    ) -> u256;

    // Set withdraw fee for a given market.
    // Only callable by contract owner.
    //
    // # Arguments
    // * `market_id` - market id
    // * `fee_rate` - fee rate
    fn set_withdraw_fee(ref self: TContractState, market_id: felt252, fee_rate: u16);

    // Transfer ownership of the contract.
    //
    // # Arguments
    // * `new_owner` - New owner of the contract
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);
    // TODO: add other functions
}
