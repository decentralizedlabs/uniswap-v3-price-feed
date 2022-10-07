# Uniswap V3 Price Feed

**A general purpose TWAP oracle based on Uniswap V3**

Uniswap V3 pools can be used as decentralized price feed oracles. However they have intrinsic limitations when used in some environments, for example:

- It's not possible to programmatically retrieve quotes for a currency pair, without knowing the pool fee;
- Since every currency pair has multiple pools, each with a different fee, it's possible to get a wrong quote by querying a pool with low liquidity;
- Liquidity constantly varies in pools, so the main pool for a currency pair can change over time;
- It can be challenging for contract developers to interact with Uniswap V3 efficiently.

## Rationale

This price feed is used by the [Slice protocol](https://slice.so) to provide dynamic pricing for products in any currency.

Slice will constantly update the pools it interacts with, however the usefulness of the price feed increases with the number of users in the Ethereum ecosystem who benefit from it.

## Functions

- `getPool`: Get the main pool for each currency pair from contract storage
- `getQuote`: Get quote given a currency pair and amount
- `updatePool`: Update the main pool for a currency pair
- `getUpdatedPool`: Get the pool for a currency pair, and update it if necessary
- `getQuoteAndUpdatePool`: Get quote given a currency pair and amount, and update pool if necessary

See the specifics in the [PriceFeed](contracts/PriceFeed.sol) contract.

## Gotchas

- Quotes represent a time-weighted average price for a currency in a certain amount of time (see [TWAP oracles](https://docs.uniswap.org/protocol/concepts/V3-overview/oracle)). As such they don&apos;t exactly correspond to the amount displayed during a swap on Uniswap, but they're better suited to estimate the value of a currency.
- While Uniswap V3 TWAP oracles are much more resilient to attacks than V2 pools, an incentivised party may still be able to manipulate the price significantly. This is especially valid for low liquidity pools.
- The price feed doesn&apos;t impose a specific TWAP interval, so care should be taken by the caller in choosing an appropriate value.

## Support (TBD)

You can support the project by donating to either its slicer or Juicebox treasury. This allows you to appear as sponsor on the slicer page or receive ERC20 tokens in exchange for your contributions, with possibly even more rewards in the future depending on how the project evolves.

### Slicer

**The slicer is owned by the contributors of this repository, proportionally to their contributions over time**. You can check the ownership distribution in the slicer page, or the specifics of each slice mint on each merged PR.

To support the project or its contributors, simply send ETH to its address (0x...). Doing so allows you to appear as sponsor in the slicer page.

### Juicebox

Our Juicebox treasury forwards any amount sent to it to the project's slicer.

When contributing on Juicebox, you will receive ERC20 tokens but won't appear as a sponsor in the slicer page.

## Contribute

When a PR is merged, an agreed amount of slices will be minted to the contributor's and reviewer's ETH addresses, granting a part of future earnings/donations related to the project.
