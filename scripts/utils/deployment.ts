/* eslint-disable no-process-exit */
/* eslint-disable node/no-unsupported-features/es-syntax */
import { readFile, writeFile } from "fs/promises";

const FILE_PATH = "./scripts/utils/deployed.json";

type Contract = {
  address: string;
  constructorArgs: any[];
  isVerified: boolean;
  isProxy: boolean;
  implementationAddr: string;
};
type Chain = { [network: string]: Contract };
type ContractFolder = { [name: string]: Chain };

export interface Root {
  list: string[];
  contracts: ContractFolder;
}

export const deployed = async (
  contractName: string,
  networkName: string,
  address: string,
  constructorArgs: any[] | undefined,
  implementationAddr: string | undefined
) => {
  console.log(`\n${contractName} deployed on ${networkName} at ${address}`);
  console.log(
    `${FILE_PATH} updated with ${contractName} on ${networkName} at ${address}\n`
  );

  // Read existant file
  let jsonString = "";
  let parsedJson: Root = { list: [], contracts: {} } as Root;

  try {
    jsonString = await readFile(FILE_PATH, "utf-8");
    parsedJson = JSON.parse(jsonString);
  } catch (e) {
    console.log("New deployed.json file created\n");
    // Do nothing
  }

  // Write or update file
  const _contract: Contract = {} as Contract;
  const _chain: Chain = {};
  const _folder: ContractFolder = {};

  // {list}
  if (!parsedJson.list.includes(contractName)) {
    parsedJson.list.push(contractName);
  }

  // {_contract}
  _contract.address = address;
  if (constructorArgs !== undefined) {
    _contract.constructorArgs = constructorArgs;
  }
  _contract.isVerified = false;

  if (implementationAddr !== undefined) {
    _contract.isProxy = true;
    _contract.implementationAddr = implementationAddr;
  } else {
    _contract.isProxy = false;
  }

  // {_chain}
  _chain[networkName] = _contract;

  // {_root}
  _folder[contractName] = {
    ...parsedJson.contracts[contractName],
    ..._chain,
  };

  // update {parsedJson}
  parsedJson.contracts = { ...parsedJson.contracts, ..._folder };

  // Store and write
  jsonString = JSON.stringify(parsedJson);
  try {
    await writeFile(FILE_PATH, jsonString);
  } catch (e) {
    console.log((e as any).message);
    throw e;
  }
};

export const verified = async (contractName: string, networkName: string) => {
  let parsedJson: Root;
  try {
    const jsonString = await readFile(FILE_PATH, "utf-8");
    parsedJson = JSON.parse(jsonString);
  } catch (e) {
    console.log("There is no deployed.json file");
    // Do nothing
    process.exit(1);
  }

  // contract exist? isVerified?
  if (
    parsedJson.contracts[contractName] !== undefined &&
    parsedJson.contracts[contractName][networkName] !== undefined
  ) {
    if (!parsedJson.contracts[contractName][networkName].isVerified) {
      parsedJson.contracts[contractName][networkName].isVerified = true;
    } else {
      console.log("The contract is already verified");
      process.exit(1);
    }
  } else {
    console.log(
      `The contract ${contractName} is not deployed on ${networkName}`
    );
    process.exit(1);
  }

  // store on deployed.json
  const storedJson = JSON.stringify(parsedJson);
  try {
    await writeFile(FILE_PATH, storedJson);
    console.log(`\nSuccessfully updated verification on deployed.json\n`);
  } catch (e) {
    console.log((e as any).message);
    throw e;
  }
};
