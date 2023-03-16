import { ethers } from "hardhat";

async function main() {
    const USDC_Factory = await ethers.getContractFactory('USDC');
    const USDC = await USDC_Factory.deploy();
    await USDC.deployed();

    console.log(`The USDC has been deployed to address: ${USDC.address}`);
}

main();