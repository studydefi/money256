require("dotenv").config({ path: "../../.env" });
const Ganache = require("ganache-core");
const { ethers } = require("ethers");

const port = 8545;
const nodeUrl = process.env.MAINNET_NODE_URL;

const server = Ganache.server({
  fork: nodeUrl,
  network_id: 1,
  gasLimit: 20000000,
  logger: { log: (x) => console.log(x) },
  accounts: [
    {
      secretKey: process.env.PK_DEPLOYER,
      balance: ethers.utils.hexlify(ethers.utils.parseEther("1000")),
    },
    {
      secretKey: process.env.PK_DISPUTER,
      balance: ethers.utils.hexlify(ethers.utils.parseEther("1000")),
    },
    {
      secretKey: process.env.PK_MINTER_1,
      balance: ethers.utils.hexlify(ethers.utils.parseEther("1000")),
    },
    {
      secretKey: process.env.PK_MINTER_2,
      balance: ethers.utils.hexlify(ethers.utils.parseEther("1000")),
    },
    {
      secretKey: process.env.PK_GENERIC_1,
      balance: ethers.utils.hexlify(ethers.utils.parseEther("1000")),
    },
  ],
});

server.listen(port, function (err, blockchain) {
  console.log("listening on port", port);
  // console.log(blockchain)
});
