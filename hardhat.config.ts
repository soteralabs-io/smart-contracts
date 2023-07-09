import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@openzeppelin/hardhat-upgrades';

const {
  ALCHEMY_KEY, // rinkeby
  ALCHEMY_GOERLI_KEY,
  INFURA_GOERLI_KEY,
  ALCHEMY_MUMBAI_KEY,
  ALCHEMY_ETHEREUM_KEY,
  ACCOUNT_PRIVATE_KEY
} = process.env;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  // defaultNetwork: "rinkeby",
  networks: {
    // hardhat: {
    //   chainId: 1337,
    //   forking: {
    //     enabled: true,
    //     url: `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_ETHEREUM_KEY}`,
    //   },
    // },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${ALCHEMY_KEY}`,
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`],
      gasPrice: 2000000000
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_GOERLI_KEY}`,
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`],
      gasPrice: 60000000
    },
    scrollAlpha: {
      url: 'https://alpha-rpc.scroll.io/l2' || '',
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`],
    },
    goerliInfura: {
      url: `https://goerli.infura.io/v3/${INFURA_GOERLI_KEY}`,
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`],
      gasPrice: 2000000000
    },
    mumbai: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${ALCHEMY_MUMBAI_KEY}`,
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`],
      gasPrice: 2000000000
    },
    ethereum: {
      chainId: 1,
      url: `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_ETHEREUM_KEY}`,
      accounts: [`0x${ACCOUNT_PRIVATE_KEY}`]
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: {
      rinkeby: process.env.ETHERSCAN_API_KEY as string,
      goerli: process.env.ETHERSCAN_API_KEY as string,
      polygonMumbai: process.env.POLYGONSCAN_API_KEY as string,
      scrollAlpha: 'abc',
    },
    customChains: [
      {
        network: 'scrollAlpha',
        chainId: 534353,
        urls: {
          apiURL: 'https://blockscout.scroll.io/api',
          browserURL: 'https://blockscout.scroll.io/',
        },
      },
    ],
  },
};

export default config;
