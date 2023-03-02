import { ethers } from "hardhat";

async function main() {
    console.log('Start Deploying');

    const Miner_Factory = await ethers.getContractFactory('Miner');
    const Miner = await Miner_Factory.deploy();

    await Miner.deployed();

    console.log(`The Miner Contract has been deployed to: ${Miner.address}`);
}

main();