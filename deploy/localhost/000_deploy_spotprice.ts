import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  await deploy('SpotPriceGetter', {
    contract: 'SpotPriceGetter',
    args: [],
    from: creator,
    log: true,
  });
};

run.tags = ['mock', 'spot-price'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
