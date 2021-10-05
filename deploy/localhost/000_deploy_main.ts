import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';

const run: DeployFunction = async (hre) => {
  const {deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  console.log('Deploy main contracts');

  const usdc = {address: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174'};
  const operator = {address: '0x974AC76c7870d941AafB03a716e1fec498808291'};

  const timelockDelay = 12 * 60 * 60; // 12 hours

  await deploy('Timelock', {
    from: creator,
    args: [creator, timelockDelay],
    log: true,
  });

  await deploy('Multicall', {
    args: [],
    from: creator,
    log: true,
  });

  const treasury = await deploy('Treasury', {
    from: creator,
    log: true,
    args: [],
  });

  const treasuryPolicy = await deploy('TreasuryPolicy', {
    from: creator,
    log: true,
    args: [],
  });

  const mintFee = 3000;
  const redeemFee = 4000;
  const excessCollateralSafetyMargin = 150000;
  const idleCollateralUtilizationRatio = 800000;
  const reservedCollateralThreshold = 150000;

  await execute(
    'TreasuryPolicy',
    {from: creator, log: true},
    'initialize',
    treasury.address,
    mintFee,
    redeemFee,
    excessCollateralSafetyMargin,
    idleCollateralUtilizationRatio,
    reservedCollateralThreshold
  );

  const collateralRatioPolicy = await deploy('CollateralRatioPolicy', {
    from: creator,
    log: true,
    args: [],
  });

  await execute('CollateralRatioPolicy', {from: creator, log: true}, 'toggleCollateralRatio');

  const collateralReserve = await deploy('CollateralReserve', {
    from: creator,
    log: true,
    args: [],
  });

  await execute('CollateralReserve', {from: creator, log: true}, 'initialize', treasury.address);

  const treasuryFund = await deploy('TreasuryFund', {
    from: creator,
    log: true,
    args: [],
  });

  await execute('TreasuryFund', {from: creator, log: true}, 'setOperator', operator.address);

  const dollar = await deploy('Dollar', {
    from: creator,
    args: [],
    log: true,
  });

  await execute(
    'Dollar',
    {from: creator, log: true},
    'initialize',
    'Tower Stablecoin',
    'TOWER',
    treasury.address
  );

  const share = await deploy('Share', {
    from: creator,
    args: [],
    log: true,
  });

  const vestingStartTime = 1633694400; // Friday, October 8, 2021 12:00:00 PM
  const communityRewardController = creator;

  await execute(
    'Share',
    {from: creator, log: true},
    'initialize',
    'Ivory Token',
    'IVORY',
    treasury.address,
    treasuryFund.address,
    communityRewardController,
    vestingStartTime
  );

  const poolUSDC = await deploy('PoolUSDC', {
    contract: 'Pool',
    from: creator,
    args: [],
    log: true,
  });

  await execute(
    'PoolUSDC',
    {from: creator, log: true},
    'initialize',
    dollar.address,
    share.address,
    usdc.address,
    treasury.address
  );

  // Pause minting/redeeming in the beginning
  await execute('PoolUSDC', {from: creator, log: true}, 'toggleMinting');
  await execute('PoolUSDC', {from: creator, log: true}, 'toggleRedeeming');

  const consolidatedFund = await deploy('ConsolidatedFund', {
    from: creator,
    log: true,
    args: [],
  });

  await execute('TreasuryFund', {from: creator, log: true}, 'initialize', share.address);
  await execute('TreasuryFund', {from: creator, log: true}, 'setOperator', operator.address);

  await execute(
    'CollateralRatioPolicy',
    {from: creator, log: true},
    'initialize',
    treasury.address,
    dollar.address
  );

  const profitSharingFund = consolidatedFund.address;
  const controller = operator;

  await execute(
    'Treasury',
    {from: creator, log: true},
    'initialize',
    dollar.address,
    share.address,
    usdc.address,
    treasuryPolicy.address,
    collateralRatioPolicy.address,
    collateralReserve.address,
    profitSharingFund,
    controller.address
  );

  await execute('Treasury', {from: creator, log: true}, 'addPool', poolUSDC.address);
};

run.tags = ['mock', 'main'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
