/* eslint-disable no-process-exit */
import hre, { ethers } from "hardhat";
import { deployed } from "./utils/deployment";

const CONTRACT_NAME = "FungibleToken";

const main = async () => {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const FungibleToken = await hre.ethers.getContractFactory(CONTRACT_NAME);
  const token = await FungibleToken.deploy(deployer.address);
  await token.deployed();

  // save into deployed.json
  await deployed(
    CONTRACT_NAME,
    hre.network.name,
    token.address,
    [deployer.address], // undefined if no constructor args
    undefined
  );
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
