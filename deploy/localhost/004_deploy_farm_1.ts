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

  const numberOfBlocksPerDay = BigNumber.from((3600 * 24) / 2); // 2 seconds block time
  const emissionRatePerDay = '383562';
  const rewardPerBlock = parseUnits(emissionRatePerDay, 18).div(numberOfBlocksPerDay);
  const startBlock = 0;

  const consolidatedFund = await ethers.getContract('ConsolidatedFund');

  const masterChefIVORY = await deploy('MasterChef_IVORY_1', {
    contract: 'MasterChef',
    args: [share.address, consolidatedFund.address, rewardPerBlock, startBlock],
    from: creator,
    log: true,
  });

  await execute(
    'ConsolidatedFund',
    {from: creator, log: true},
    'addPool',
    masterChefIVORY.address,
    share.address
  );
};

run.tags = ['mock', 'farm-1'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
