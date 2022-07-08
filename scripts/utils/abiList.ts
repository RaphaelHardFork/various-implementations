/* eslint-disable node/no-unsupported-features/es-syntax */
/* eslint-disable no-process-exit */
import { readFile, writeFile } from "fs/promises";
import { Root } from "./deployment";
import hre from "hardhat";

/**
 * This function is used to create a file with address and ABI in order to import
 * into the front-end repository.
 * The file created is specific to a network
 */

// This file is then imported in the front-end
const FILE_PATH = "./scripts/utils/contracts.json";

type Contract = {
  address: string;
  abi: any[];
};
type ContractName = { [name: string]: Contract };
type Chain = { [network: string]: ContractName };

const createList = async () => {
  let parsedJson: Root;
  try {
    parsedJson = JSON.parse(
      await readFile("./scripts/utils/deployed.json", "utf-8")
    );
  } catch (e) {
    console.log("Cannot read deployed.json or no deployed.json file");
    process.exit(1);
  }

  // Write or update file
  const _contract: Contract = {} as Contract;
  const _contractName: ContractName = {};
  const _chain: Chain = {};

  for (const contract of parsedJson.list) {
    _contract.address =
      parsedJson.contracts[contract][hre.network.name].address;

    const file: any = await readFile(`out/${contract}.sol/${contract}.json`);
    const abi = JSON.parse(file).abi;
    _contract.abi = abi;
    _contractName[contract] = { ..._contract };
  }
  _chain[hre.network.name] = _contractName;

  const jsonString = JSON.stringify(_chain);

  try {
    await writeFile(FILE_PATH, jsonString);
  } catch (e) {
    console.log(e);
  }
};

createList();
