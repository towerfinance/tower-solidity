import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  const treasury = await ethers.getContract('Treasury');
  const oracleCollateral = await ethers.getContract('CollateralOracle');

  const dollar = await ethers.getContract('Dollar');
  const share = await ethers.getContract('Share');
  const usdc = {address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'};

  const routerFirebird = {address: '0xF6fa9Ea1f64f1BBfA8d71f7f43fAF6D45520bfac'};
  const routerPath = [usdc.address, share.address];

  await deploy('ZapPool', {
    contract: 'ZapPool',
    args: [],
    from: creator,
    log: true,
  });

  await execute(
    'ZapPool',
    {from: creator, log: true},
    'initialize',
    treasury.address,
    dollar.address,
    share.address,
    usdc.address,
    oracleCollateral.address
  );

  // Pause minting in the beginning
  await execute('ZapPool', {from: creator, log: true}, 'toggleMinting');

  await execute(
    'ZapPool',
    {from: creator, log: true},
    'setRouter',
    routerFirebird.address,
    routerPath
  );
};

run.tags = ['mock', 'zap'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
