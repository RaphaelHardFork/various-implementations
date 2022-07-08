/* eslint-disable no-process-exit */
import { readFile } from "fs/promises";
import hre, { run } from "hardhat";
import { Root, verified } from "./deployment";

const main = async () => {
  let parsedJson: Root;
  try {
    parsedJson = JSON.parse(
      await readFile("./scripts/utils/deployed.json", "utf-8")
    );
  } catch (e) {
    console.log("Cannot read deployed.json or no deployed.json file");
    process.exit(1);
  }

  console.log(`Verifying following contracts on ${hre.network.name}:`);

  for (const contractName of parsedJson.list) {
    if (!parsedJson.contracts[contractName][hre.network.name].isVerified) {
      try {
        console.log(`${contractName} verification on ${hre.network.name}...`);
        await run("verify:verify", {
          address: parsedJson.contracts[contractName][hre.network.name].address,
          constructorArguments:
            parsedJson.contracts[contractName][hre.network.name]
              .constructorArgs,
        });
        await verified(contractName, hre.network.name);
      } catch (e) {
        console.log(e);
        continue;
      }
    } else {
      console.log(`${contractName} already verified`);
    }
  }
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
