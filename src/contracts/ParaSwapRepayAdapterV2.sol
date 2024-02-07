// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from '@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol';
import {IParaSwapAugustusRegistry} from '../interfaces/IParaSwapAugustusRegistry.sol';
import {DataTypes, ILendingPool} from 'aave-address-book/AaveV2.sol';
import {BaseParaSwapAdapter} from './BaseParaSwapAdapter.sol';
import {ParaSwapRepayAdapter} from './ParaSwapRepayAdapter.sol';

/**
 * @title ParaSwapRepayAdapterV2
 * @notice ParaSwap Adapter to repay debt with collateral.
 * @dev It is specifically designed for Aave V2
 * @author Aave Labs
 **/
contract ParaSwapRepayAdapterV2 is ParaSwapRepayAdapter {
  /**
   * @dev Constructor
   * @param addressesProvider The address of the Aave PoolAddressesProvider contract
   * @param pool The address of the Aave Pool contract
   * @param augustusRegistry The address of the Paraswap AugustusRegistry contract
   * @param owner The address of the owner
   */
  constructor(
    IPoolAddressesProvider addressesProvider,
    address pool,
    IParaSwapAugustusRegistry augustusRegistry,
    address owner
  ) ParaSwapRepayAdapter(addressesProvider, pool, augustusRegistry, owner) {}

  /// @inheritdoc BaseParaSwapAdapter
  function _getReserveData(
    address asset
  ) internal view override returns (address, address, address) {
    DataTypes.ReserveData memory reserveData = ILendingPool(address(POOL)).getReserveData(asset);
    return (
      reserveData.variableDebtTokenAddress,
      reserveData.stableDebtTokenAddress,
      reserveData.aTokenAddress
    );
  }

  /// @inheritdoc BaseParaSwapAdapter
  function _supply(
    address asset,
    uint256 amount,
    address to,
    uint16 referralCode
  ) internal override {
    ILendingPool(address(POOL)).deposit(asset, amount, to, referralCode);
  }
}