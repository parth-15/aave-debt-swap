// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Detailed} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {AaveGovernanceV2} from 'aave-address-book/AaveGovernanceV2.sol';
import {Errors} from 'aave-address-book/AaveV3.sol';
import {AaveV3Ethereum, AaveV3EthereumAssets, IPool} from 'aave-address-book/AaveV3Ethereum.sol';
import {BaseTest} from './utils/BaseTest.sol';
import {ParaSwapWithdrawSwapAdapterV3} from '../src/contracts/ParaSwapWithdrawSwapAdapterV3.sol';
import {AugustusRegistry} from '../src/lib/AugustusRegistry.sol';
import {IParaSwapWithdrawSwapAdapter} from '../src/interfaces/IParaSwapWithdrawSwapAdapter.sol';
import {IBaseParaSwapAdapter} from '../src/interfaces/IBaseParaSwapAdapter.sol';
import {stdMath} from 'forge-std/StdMath.sol';

contract WithdrawSwapAdapterV3Test is BaseTest {
  ParaSwapWithdrawSwapAdapterV3 internal withdrawSwapAdapter;

  function setUp() public override {
    super.setUp();
    vm.createSelectFork(vm.rpcUrl('mainnet'), 19125717);

    withdrawSwapAdapter = new ParaSwapWithdrawSwapAdapterV3(
      IPoolAddressesProvider(address(AaveV3Ethereum.POOL_ADDRESSES_PROVIDER)),
      address(AaveV3Ethereum.POOL),
      AugustusRegistry.ETHEREUM,
      AaveGovernanceV2.SHORT_EXECUTOR
    );
  }

  function test_revert_due_to_slippage_withdrawSwap() public {
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 10 ether;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    IERC20Detailed(collateralAssetAToken).approve(address(withdrawSwapAdapter), withdrawAmount);

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount,
      user,
      true,
      true
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('minAmountToReceive exceeds max slippage'));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_revert_wrong_paraswap_route() public {
    address daiAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 100 ether;

    vm.startPrank(user);
    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    IERC20Detailed(daiAToken).approve(address(withdrawSwapAdapter), withdrawAmount);
    // generating the paraswap route for half of withdrawAmount and executing swap with withdrawAmount
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount / 2,
      user,
      true,
      false
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert();
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_revert_withdrawSwap_max_collateral() public {
    address aToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;

    uint256 supplyAmount = 120 ether;
    uint256 withdrawAmount = 120 ether;
    uint256 expectedAmount = 115 ether;

    vm.startPrank(user);

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      withdrawAmount,
      user,
      true,
      true
    );
    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: withdrawAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory collateralATokenPermit;

    vm.expectRevert(bytes('INSUFFICIENT_AMOUNT_TO_SWAP'));
    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, collateralATokenPermit);
  }

  function test_withdrawSwap_swapHalf() public {
    vm.startPrank(user);
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    uint256 swapAmount = 5_000 ether; // supplyAmount/2
    uint256 expectedAmount = 4500 ether;

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      false
    );
    IERC20Detailed(collateralAssetAToken).approve(address(withdrawSwapAdapter), swapAmount);

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: 4000 ether,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });
    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);

    assertEq(
      _withinRange(
        collateralAssetATokenBalanceAfter,
        collateralAssetATokenBalanceBefore,
        swapAmount + 1
      ),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function test_withdrawSwap_swapHalf_with_permit() public {
    vm.startPrank(user);
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 10_000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    uint256 swapAmount = 5_000 ether; // supplyAmount/2
    uint256 expectedAmount = 4500 ether;

    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      false
    );

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory tokenPermit = _getPermit(
      collateralAssetAToken,
      address(withdrawSwapAdapter),
      swapAmount
    );

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateralAssetATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);
    assertEq(
      _withinRange(
        collateralAssetATokenBalanceAfter,
        collateralAssetATokenBalanceBefore,
        swapAmount + 1
      ),
      true,
      'INVALID_ATOKEN_AMOUNT_AFTER_WITHDRAW_SWAP'
    );
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function test_withdrawSwap_swapFull() public {
    vm.startPrank(user);
    address collateralAsset = AaveV3EthereumAssets.DAI_UNDERLYING;
    address collateralAssetAToken = AaveV3EthereumAssets.DAI_A_TOKEN;
    address newAsset = AaveV3EthereumAssets.LUSD_UNDERLYING;
    address newAssetAToken = AaveV3EthereumAssets.LUSD_A_TOKEN;

    uint256 supplyAmount = 1000 ether;

    _supply(AaveV3Ethereum.POOL, supplyAmount, collateralAsset);

    skip(1 hours);

    uint256 swapAmount = 1001 ether;
    uint256 expectedAmount = 950 ether;
    PsPResponse memory psp = _fetchPSPRoute(
      collateralAsset,
      newAsset,
      swapAmount,
      user,
      true,
      true
    );

    IParaSwapWithdrawSwapAdapter.WithdrawSwapParams
      memory withdrawSwapParams = IParaSwapWithdrawSwapAdapter.WithdrawSwapParams({
        oldAsset: collateralAsset,
        oldAssetAmount: swapAmount,
        newAsset: newAsset,
        minAmountToReceive: expectedAmount,
        allBalanceOffset: psp.offset,
        user: user,
        paraswapData: abi.encode(psp.swapCalldata, psp.augustus)
      });

    IBaseParaSwapAdapter.PermitInput memory tokenPermit;

    uint256 collateralAssetATokenBalanceBefore = IERC20Detailed(collateralAssetAToken).balanceOf(
      user
    );
    uint256 newAssetBalanceBefore = IERC20Detailed(newAsset).balanceOf(user);

    IERC20Detailed(collateralAssetAToken).approve(
      address(withdrawSwapAdapter),
      collateralAssetATokenBalanceBefore
    );

    withdrawSwapAdapter.withdrawAndSwap(withdrawSwapParams, tokenPermit);

    uint256 collateralATokenBalanceAfter = IERC20Detailed(collateralAssetAToken).balanceOf(user);
    uint256 newAssetBalanceAfter = IERC20Detailed(newAsset).balanceOf(user);
    assertEq(collateralATokenBalanceAfter, 0, 'NON_ZERO_ATOKEN_BALANCE_AFTER_WITHDRAW_SWAP');
    assertGt(
      newAssetBalanceAfter - newAssetBalanceBefore,
      expectedAmount,
      'invalid amount received'
    );
    _invariant(address(withdrawSwapAdapter), collateralAsset, newAsset);
  }

  function _withinRange(uint256 a, uint256 b, uint256 diff) internal returns (bool) {
    return stdMath.delta(a, b) <= diff;
  }

  function _supply(IPool pool, uint256 amount, address asset) internal {
    deal(asset, user, amount);
    IERC20Detailed(asset).approve(address(pool), amount);
    pool.deposit(asset, amount, user, 0);
  }

  function _borrow(IPool pool, uint256 amount, address asset) internal {
    pool.borrow(asset, amount, 2, 0, user);
  }

  function _withdraw(IPool pool, uint256 amount, address asset) internal {
    pool.withdraw(asset, amount, user);
  }
}