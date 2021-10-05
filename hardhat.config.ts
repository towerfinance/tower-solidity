import 'dotenv/config';
import {HardhatUserConfig} from 'hardhat/types';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import 'hardhat-gas-reporter';
import {task} from 'hardhat/config';
import {accounts, node_url} from './utils/networks';
import {assert} from 'console';

task('accounts', 'Prints the list of accounts', async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

// Sending test tokens on Mumbai
// example: hh send-test-tokens --amount 1 --receiver 0x5F6dAF1726C29D85eA4Adc81Ccd137E39Aa2d9cB --network mumbai
task('send-test-tokens', 'Send test tokens on Mumbai')
  .addParam('amount', 'Sending amount')
  .addParam('receiver', 'Address of receiver')
  .setAction(async (args, hre) => {
    assert(hre.network.name === 'mumbai', 'Only works on Mumbai');

    const ethers = hre.ethers;
    const receiver = args.receiver;
    const amount = args.amount;

    const {creator} = await ethers.getNamedSigners();

    const share = await ethers.getContract('Share');
    const dollar = await ethers.getContract('Dollar');
    const mockUsdc = await ethers.getContract('MockCollateral');
    const dollarUsdcFLP = await ethers.getContract('MockFirebirdPair_DOLLAR_USDC');
    const shareUsdcFLP = await ethers.getContract('MockFirebirdPair_SHARE_USDC');

    console.log(`Sending test tokens to ${receiver}`);

    await share.connect(creator).transfer(receiver, ethers.utils.parseEther(amount));
    await dollar.connect(creator).transfer(receiver, ethers.utils.parseEther(amount));
    await mockUsdc.connect(creator).mint(receiver, ethers.utils.parseEther(amount));
    await dollarUsdcFLP.connect(creator).transfer(receiver, ethers.utils.parseEther(amount));
    await shareUsdcFLP.connect(creator).transfer(receiver, ethers.utils.parseEther(amount));

    console.log('done');
  });

let config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.4',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      accounts: accounts('localhost'),
    },
    localhost: {
      url: 'http://localhost:8545',
      accounts: accounts('localhost'),
    },
    mumbai: {
      url: node_url('mumbai') || '',
      accounts: accounts('mumbai'),
      live: true,
    },
    matic_staging: {
      url: node_url('matic') || '',
      accounts: accounts('matic'),
      live: true,
    },
    matic: {
      url: node_url('matic') || '',
      accounts: accounts('matic'),
      live: true,
    },
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 5,
    enabled: !!process.env.REPORT_GAS,
  },
  namedAccounts: {
    creator: 0,
  },
};

if (process.env.FORK_MAINNET === 'true' && config.networks) {
  console.log('FORK_MAINNET is set to true');
  config = {
    ...config,
    networks: {
      ...config.networks,
      hardhat: {
        ...config.networks.hardhat,
        forking: {
          url: node_url('matic'),
          blockNumber: 19833433,
        },
        chainId: 1,
      },
    },
  };
}

export default config;
