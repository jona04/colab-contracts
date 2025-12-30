// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ClientVault} from "../src/core/ClientVault.sol";
import {IConcentratedLiquidityAdapter} from "../src/interfaces/IConcentratedLiquidityAdapter.sol";

interface IERC20Metadata {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);
}

contract ViewClientVaultState is Script {
    function run() external view {
        // endereço do vault vem por env: VAULT_ADDR
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        ClientVault vault = ClientVault(vaultAddr);

        console2.log("========== ClientVault State ==========");
        console2.log("chainId:", block.chainid);
        console2.log("vault:  ", vaultAddr);

        // wiring básico
        address owner = vault.owner();
        address executor = vault.executor();
        IConcentratedLiquidityAdapter adapter = vault.adapter();
        address adapterAddr = address(adapter);
        address dexRouter = vault.dexRouter();
        address feeCollector = vault.feeCollector();
        uint256 strategyId = vault.strategyId();

        console2.log("owner:       ", owner);
        console2.log("executor:    ", executor);
        console2.log("adapter:     ", adapterAddr);
        console2.log("dexRouter:   ", dexRouter);
        console2.log("feeCollector:", feeCollector);
        console2.log("strategyId:  ", strategyId);

        // automation config
        (
            bool enabled,
            uint32 cooldown,
            uint16 slippageBps,
            bool swapAllowed
        ) = vault.getAutomationConfig();

        console2.log("automationEnabled:", enabled);
        console2.log("cooldownSec:      ", cooldown);
        console2.log("maxSlippageBps:   ", slippageBps);
        console2.log("allowSwap:        ", swapAllowed);

        uint256 lastReb = vault.lastRebalanceTs();
        console2.log("lastRebalanceTs:  ", lastReb);
        if (lastReb > 0 && block.timestamp >= lastReb) {
            console2.log(
                "secondsSinceLastRebalance:",
                block.timestamp - lastReb
            );
        }

        uint256 positionTokenId = vault.positionTokenId();
        console2.log("positionTokenId:  ", positionTokenId);

        // tokens da estratégia
        (address token0, address token1) = adapter.tokens();
        console2.log("token0:", token0);
        console2.log("token1:", token1);

        IERC20Metadata erc0 = IERC20Metadata(token0);
        IERC20Metadata erc1 = IERC20Metadata(token1);

        string memory sym0 = erc0.symbol();
        string memory sym1 = erc1.symbol();
        uint8 dec0 = erc0.decimals();
        uint8 dec1 = erc1.decimals();

        console2.log("token0 symbol:  ", sym0);
        console2.log("token0 decimals:", dec0);
        console2.log("token1 symbol:  ", sym1);
        console2.log("token1 decimals:", dec1);

        // saldos do vault
        uint256 bal0 = erc0.balanceOf(vaultAddr);
        uint256 bal1 = erc1.balanceOf(vaultAddr);

        console2.log("vault balance token0 (raw):", bal0);
        console2.log("vault balance token1 (raw):", bal1);

        uint256 scale0 = 10 ** dec0;
        uint256 scale1 = 10 ** dec1;

        console2.log("vault balance token0 (truncado):", bal0 / scale0);
        console2.log("vault balance token1 (truncado):", bal1 / scale1);

        console2.log("=======================================");
    }
}
