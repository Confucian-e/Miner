import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/types";
dotenv.config({ path: './.env' });

const ALCHEMY_API_KEY = process.env.Alchemy_api_key;
const PRIVATE_KEY: string = process.env.Private_key!;
const ETHERSCAN_API_KEY = process.env.Etherscan_api_key;

const config: HardhatUserConfig = {
  networks: {
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
      accounts: [PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },

  solidity: "0.8.17"
}

export default config;