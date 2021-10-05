import {DeployFunction} from 'hardhat-deploy/types';
import 'hardhat-deploy-ethers';
import 'hardhat-deploy';

const run: DeployFunction = async (hre) => {
  const {ethers, deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  const dollar = await ethers.getContract('Dollar');
  const share = await ethers.getContract('Share');
  const operator = {address: '0x974AC76c7870d941AafB03a716e1fec498808291'};

  const lp_dollar_usdc = {address: '0xd70f14f13ef3590e537bbd225754248965a3593c'};
  const lp_share_usdc = {address: '0x10995233Ef7b3abd1a2706a86FFeA456ebae8796'};

  const priceFeed_USDC_USD = {address: '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7'};

  const oracle_DOLLAR_USDC = await deploy('PairOracle_DOLLAR_USDC', {
    contract: 'PairOracle',
    args: [lp_dollar_usdc.address],
    from: creator,
    log: true,
  });

  await execute(
    'PairOracle_DOLLAR_USDC',
    {from: creator, log: true},
    'setOperator',
    operator.address
  );

  const oracle_SHARE_USDC = await deploy('PairOracle_SHARE_USDC', {
    contract: 'PairOracle',
    args: [lp_share_usdc.address],
    from: creator,
    log: true,
  });

  const oraclePeriod = 10 * 60; // 10 min TWAP
  await execute('PairOracle_SHARE_USDC', {from: creator, log: true}, 'setPeriod', oraclePeriod);
  await execute(
    'PairOracle_SHARE_USDC',
    {from: creator, log: true},
    'setOperator',
    operator.address
  );

  const oracleCollateral = await deploy('CollateralOracle', {
    args: [priceFeed_USDC_USD.address],
    from: creator,
    log: true,
  });

  const oracleDollar = await deploy('DollarOracle', {
    contract: 'PriceOracle',
    args: [dollar.address, oracle_DOLLAR_USDC.address, oracleCollateral.address, 12],
    from: creator,
    log: true,
  });

  const oracleShare = await deploy('ShareOracle', {
    contract: 'PriceOracle',
    args: [share.address, oracle_SHARE_USDC.address, oracleCollateral.address, 12],
    from: creator,
    log: true,
  });

  await execute(
    'CollateralRatioPolicy',
    {from: creator, log: true},
    'setOracleDollar',
    oracleDollar.address
  );
  await execute('PoolUSDC', {from: creator, log: true}, 'setOracle', oracleCollateral.address);
  await execute('Treasury', {from: creator, log: true}, 'setOracleDollar', oracleDollar.address);
  await execute('Treasury', {from: creator, log: true}, 'setOracleShare', oracleShare.address);
  await execute(
    'Treasury',
    {from: creator, log: true},
    'setOracleCollateral',
    oracleCollateral.address
  );
};

run.tags = ['mock', 'oracles'];

run.skip = async (hre) => {
  return hre.network.name !== 'localhost' && hre.network.name !== 'hardhat';
};
export default run;
