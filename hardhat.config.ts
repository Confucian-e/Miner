import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/types";
dotenv.config({ path: './.env' });

const ALCHEMY_API_KEY = process.env.Alchemy_api_key;
const PRIVATE_KEY = process.env.Private_key!;
const Etherscan_API_KEY = process.env.Etherscan_api_key;
const BSC_TestNet_RPC = process.env.BSC_TestNet_RPC;
const BscScan_API_KEY = process.env.BscScan_api_key;

const BscMainnet_PRC = process.env.BscMainnet_PRC;
const Work_Private_key = process.env.Work_Private_key!;

const config: HardhatUserConfig = {
  defaultNetwork: 'bsc_testnet',
  networks: {
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
      accounts: [PRIVATE_KEY],
    },
    bsc_testnet: {
      url: `${BSC_TestNet_RPC}`,
      accounts: [PRIVATE_KEY],
    },

    bsc: {
      url: `${BscMainnet_PRC}`,
      accounts: [Work_Private_key],
    },
  },

  etherscan: {
    apiKey: {
      goerli: Etherscan_API_KEY!,
      bscTestnet: BscScan_API_KEY!,
      bsc: BscScan_API_KEY!,
    }
  },

  solidity: "0.8.9",

  abiExporter: {
    path: './abi',
    runOnCompile: true,
    clear: true,
    flat: true,
    only: [],
    spacing: 2,
    pretty: false,
    // format: "json",
  }
}

export default config;