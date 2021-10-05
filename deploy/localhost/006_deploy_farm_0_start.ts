import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';
import {parseUnits} from '@ethersproject/units';
import {BigNumber} from 'ethers';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  const share = await ethers.getContract('Share');

  const lp_share_usdc = {address: '0x10995233Ef7b3abd1a2706a86FFeA456ebae8796'};

  const startBlock = 0;

  await execute('MasterChef_IVORY_0', {from: creator, log: true}, 'setStartBlockOnce', startBlock);

  const allocPoint = {
    ivorySingle: 25000, // allocPoint: 25%
    ivoryUsdc: 75000, // allocPoint: 75%
  };

  // IVORY single vault
  await execute(
    'MasterChef_IVORY_0',
    {from: creator, log: true},
    'add',
    allocPoint.ivorySingle,
    share.address
  );

  // IVORY/USDC FLP
  await execute(
    'MasterChef_IVORY_0',
    {from: creator, log: true},
    'add',
    allocPoint.ivoryUsdc,
    lp_share_usdc.address
  );

  await execute('MasterChef_IVORY_0', {from: creator, log: true}, 'massUpdatePools');
};

run.tags = ['mock', 'farm-0-start'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
