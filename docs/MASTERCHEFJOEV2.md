# MasterChefJoeV2 and Double Reward Farms

MasterChefJoeV2 is a modified version of Sushi's MasterChefV2, which allows farms to offer two rewards instead of one.

For example, instead of just rewarding JOE, it has the ability to offer JOE **and** your project's token.

## How It Works

The only thing you need to get this to work with MasterChefJoeV2 is to implement a contract that conforms to the IRewarder interface.

This interface describes two functions:

```sol
interface IRewarder {
    using SafeERC20 for IERC20;
    function onJoeReward(address user, uint256 newLpAmount) external;
    function pendingTokens(address user) external view returns (uint256 pending);
}
```

`pendingTokens` is purely for displaying stats on the frontend. 

The most important is `onJoeReward`, which is called whenever a user harvests from our MasterChefJoeV2.

It is in this function where you would want to contain the logic to mint/transfer your project's tokens to the user. 

The implementation is completely up to you. But to make your life easier, we have implemented two sample rewarder contracts and their accompanying tests.
Both of these assume your project uses a Sushi-style MasterChef contract, except one rewards per block and the other rewards per second:
- [contracts/mocks/MasterChefRewarderPerBlockMock.sol](contracts/mocks/MasterChefRewarderPerBlockMock.sol)
- [contract/mocks/MasterChefRewarderPerSecMock.sol](contract/mocks/MasterChefRewarderPerSecMock.sol)
- [test/MasterChefJoeV2.test.ts](test/MasterChefJoeV2.test.ts)

## Example of How It Works with Sushi-style MasterChef

![Image of Double Reward Farming](MasterChefJoeV2.png)

Here we assume that your project uses a Sushi-style MasterChef:

Setup:
1. Create a new dummy token, `DUMMY`, with supply of 1 (in Wei).
2. Transfer 1 `DUMMY` to the deployer and then renouncen ownership of the token.
3. Create a new pool in your MasterChef for `DUMMY`.
4. Deploy the IRewarder contract.
5. Approve the IRewarder contract to spend 1 `DUMMY`.
6. Call the `init()` method in IRewarder contract, passing in the `DUMMY` token address - this will allow the IRewarder to deposit the dummy token into your MasterChef and start receiving your rewards.
7. JOE-XYZ LP with the above IRewarder contract is added as pool to MasterChefJoeV2.
8. Users can now deposit JOE-XYZ LPs into the pool.
9. Each time user harvests from MasterChefJoeV2, he/she receives both JOE and XYZ.

## Tests

We encourage you to check out our unit tests in test/MasterChefJoe.test.ts.

MasterChefJoeV2 rewards per second, but is compatible with MasterChefs that reward both per block or per second. In the test file you will find tests for both.

A quick note about testing with timestamp: it's less predictable than testing with blocks so instead of asserting the reward is an exact amount, we assert it falls within a certain range.

**To run:** 
```
yarn test test/MasterChefJoeV2.test.ts
```

**To run coverage:** 
```
yarn test:coverage --testfiles "test/MasterChefJoeV2.test.ts"
```

**Coverage results:**

File | Statements | Branches
--- | --- | ---
MasterChefJoeV2.sol | 100% | 100%
MasterChefRewarderPerBlockMock.sol | 98.15% | 90.91%
MasterChefRewarderPerSecMock.sol | 98.15% | 90.91%

Notes:
- Rewarder mocks have branches that are really hard to hit, hence why statements are not 100%.
- Same with the branches.
