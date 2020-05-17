# money256
Entry to hackmoney

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

3. Run `npm test` inside the `smart-contracts` package to run the test.
