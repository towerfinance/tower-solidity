import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  const treasury = await ethers.getContract('Treasury');
  const collateralReserve = await ethers.getContract('CollateralReserve');
  const share = await ethers.getContract('Share');

  const operator = {address: '0x974AC76c7870d941AafB03a716e1fec498808291'};

  const usdc = {address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'};
  const wmatic = {address: '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270'};

  // https://docs.aave.com/developers/v/2.0/deployed-contracts/matic-polygon-market
  const aaveLendingPool = {address: '0x8dff5e27ea6b7ac08ebfdf9eb090f32ee9a30fcf'};
  const aaveIncentivesController = {address: '0x357D51124f59836DeD84c8a1730D72B749d8BC23'};
  const routerQuickSwap = {address: '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff'};
  const routerFirebird = {address: '0xF6fa9Ea1f64f1BBfA8d71f7f43fAF6D45520bfac'};
  const routerPaths = {
    wmatic: [wmatic.address, usdc.address],
    usdc: [usdc.address, share.address],
  };

  //////////////////////
  // TreasuryVaultAave
  //////////////////////
  const treasuryVaultAave = await deploy('TreasuryVaultAave', {from: creator, args: [], log: true});
  await execute(
    'TreasuryVaultAave',
    {from: creator, log: true},
    'initialize',
    usdc.address,
    treasury.address,
    aaveLendingPool.address,
    aaveIncentivesController.address
  );

  //////////////////////
  // VaultController
  //////////////////////
  const admin = operator;
  const vaultController = await deploy('VaultController', {
    from: creator,
    args: [],
    log: true,
  });

  await execute(
    'VaultController',
    {from: creator, log: true},
    'initialize',
    treasuryVaultAave.address,
    admin.address,
    collateralReserve.address,
    share.address
  );
  await execute(
    'VaultController',
    {from: creator, log: true},
    'setSwapOptions',
    routerQuickSwap.address,
    routerPaths.wmatic
  );
  await execute(
    'VaultController',
    {from: creator, log: true},
    'setSwapOptions',
    routerFirebird.address,
    routerPaths.usdc
  );

  //////////////////////
  // TreasuryVault transfer ownership from deployer to VaultController
  //////////////////////
  await execute(
    'TreasuryVaultAave',
    {from: creator, log: true},
    'transferOwnership',
    vaultController.address
  );
};

run.tags = ['mock', 'vaults'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
