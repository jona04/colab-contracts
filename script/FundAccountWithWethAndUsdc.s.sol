// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/StdCheats.sol";

interface IWETH {
    function deposit() external payable;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Script DEV: dá WETH real e USDC "forjado" (via cheatcode) para a conta.
/// - Converte 1 ETH -> 1 WETH no contrato WETH real.
/// - Seta o saldo de USDC da conta diretamente usando `deal()` (somente em fork/anvil).
contract FundAccountWithWethAndUsdc is Script, StdCheats {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY"); // mesma PK da 0xf39f...
        address user = vm.addr(pk);

        // Endereços em Base
        address WETH = 0x4200000000000000000000000000000000000006;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        // -----------------------------
        // 1) Depositar 1 ETH -> WETH
        // -----------------------------
        vm.startBroadcast(pk);

        // Garante que tem ETH suficiente (opcional; anvil já dá muito ETH)
        // vm.deal(user, 100 ether);

        IWETH(WETH).deposit{value: 1 ether}();

        vm.stopBroadcast();

        // -----------------------------
        // 2) Forjar saldo de USDC
        // -----------------------------
        // USDC tem 6 casas decimais → 5_000 USDC = 5_000 * 1e6
        uint256 usdcAmount = 5_000 * 1e6;

        // `deal` é cheatcode do Foundry (StdCheats)
        // - Ajusta diretamente o storage do token.
        // - Último parâmetro `true` ajusta também o totalSupply.
        deal(USDC, user, usdcAmount, true);

        // Logs pra você conferir no forge output
        uint256 finalWeth = IERC20Like(WETH).balanceOf(user);
        uint256 finalUsdc = IERC20Like(USDC).balanceOf(user);

        console2.log("User:", user);
        console2.log("Saldo final WETH (wei):", finalWeth);
        console2.log("Saldo final USDC (6 dec):", finalUsdc);
    }
}
