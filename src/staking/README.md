# Staking contract

This contract allow to distribute token block per block. This contract is not gas-optimised.

This contract implement the `IERC900` staking interface, is this is relevant?

**This contract is not audited**, feel free to open issues, comments, ...

## Test coverage

~60%
```
forge test --match-contract StakingVaultERC20
```