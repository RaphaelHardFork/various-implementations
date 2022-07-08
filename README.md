# Solidity TypeScript Template

![](https://img.shields.io/badge/Node.js-v16.15.0-blue)

## After cloning

```
yarn
forge update
```

Then add a `.env` file following the `.env.exemple` file

## Using

- Write smart contracts in `src`
- Write unit tests in **Solidity** using [Foundry](https://book.getfoundry.sh/forge/writing-tests.html) in `src/test`
- **OR**
- in **Javascript/Typescript** in `test`, you can use _typechain_ (once compilled) in TS

- Then deploy with scripts, you can use `deployed` function in your scripts ([see exemple](https://github.com/RaphaelHardFork/solidity-ts-template/blob/main/scripts/fungibleToken.ts#L16)) to save a track of your deployed contract in `deployed.json`

```
  npx hardhat run --network rinkeby scripts/yourScript.ts
```

## Verify contracts

Run the script `scripts/utils/verify.ts`, this should be used once the `deployed.json` is writen (after deployments).

_Always verify the constructor arguments, it can prevent from running this script_

## Create the ABI list

After deployment, and if you have a `deployed.json` file you can create the list of contracts with `address` and `abi` in orer to export into the front-end repository:

```
npx hardhat run --network rinkeby scripts/utils/abiList.ts
```

## Contract size and gas report

- contracts-sizer: https://www.npmjs.com/package/hardhat-contract-sizer
- gas-report: included in Foundry (https://book.getfoundry.sh/forge/gas-reports.html)

## Not added yet

- Upgradeable contracts, with the upgraded function for the `deployed.json`, to know the implementation address.
- Signature utils
