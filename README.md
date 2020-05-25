# money256
An entry for the [HackMoney](https://hackathon.money/) hackathon.

This project builds on top of [UpSideDai](https://github.com/Daichotomy/UpSideDai)'s concepts to create a [CFD](https://en.wikipedia.org/wiki/Contract_for_difference) that is:

1. Leveraged
2. Fully backed by some collateral (e.g. DAI) at every given step
3. Priceless (i.e. does not require a live price feed)

This Priceless CFD project can be seen as an "optimistic" CFD that is also leveraged, and fully backed by collateral. Should the CFD contract exceed the price boundary then a settlement request can be submitted. That request can also be disputed (usually by bots), and everyone is incentivized to report back the correct value of the underlying in order to prevent being penalized.

This repo is a proof of concept.

## How it's made

This project uses React + Next.js for the frontend, Truffle to compile the contracts, Solidity for the contract source code, and a bunch of code from UMA to mimic their "priceless" system, e.g.

1. Mock Oracles
2. Finder
3. Whitelist
4. Identifiers

The bot is written in Node.js using Ethers.js with a pub/sub method to listen to events.

## Setup

1. Make a `.env` file in this directory with the following contents (fill in your own):

```
PK_DEPLOYER=0x1234...
PK_DISPUTER=0x1234...
PK_MINTER_1=0x1234...
PK_MINTER_2=0x1234...
PK_GENERIC_1=0x1234...
MAINNET_NODE_URL=https://mainnet.infura.io/v3/API_KEY_HERE
```

2. Run `npm start` inside the `smart-contracts` package to start a chain forked from Mainnet.

3. Run `npx truffle migrate --network development` to migrate the contracts to the chain.

3. Run `npm test` inside the `smart-contracts` package to run the test.
