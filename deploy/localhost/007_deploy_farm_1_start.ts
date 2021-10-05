import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';
import {parseUnits} from '@ethersproject/units';
import {BigNumber} from 'ethers';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  const lp_dollar_usdc = {address: '0xd70f14f13ef3590e537bbd225754248965a3593c'};

  const startBlock = 0;

  await execute('MasterChef_IVORY_1', {from: creator, log: true}, 'setStartBlockOnce', startBlock);

  await execute(
    'MasterChef_IVORY_1',
    {from: creator, log: true},
    'add',
    100000,
    lp_dollar_usdc.address
  );

  await execute('MasterChef_IVORY_1', {from: creator, log: true}, 'massUpdatePools');
};

run.tags = ['mock', 'farm-1-start'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
