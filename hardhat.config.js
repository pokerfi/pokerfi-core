require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");

require("dotenv").config();

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
        },
        localhost: {
            url: "http://127.0.0.1:8545"
        },
        testnet: {
            url: process.env.TESTNET_RPC_URL,
            chainId: process.env.TESTNET_CHAINID | 97,
            gasPrice: 6000000000,
            accounts: { mnemonic: process.env.MNEMONIC }
        },
        mainnet: {
            url: process.env.MAINNET_RPC_URL,
            chainId: process.env.MAINNET_CHAINID | 56,
            gasPrice: 6000000000,
            accounts: { mnemonic: process.env.MNEMONIC }
        }
    },
    etherscan: {
        apiKey: process.env.BSCSCAN_API_KEY
    },
    solidity: {
        version: "0.8.0",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    }
};
