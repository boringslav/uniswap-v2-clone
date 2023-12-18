// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";

contract UniswapV2PairTest is Test {
    ERC20Mintable public token0;
    ERC20Mintable public token1;
    UniswapV2Pair public pair;

    uint256 constant MINIMUM_LIQUIDITY = 1000; // 1e15

    function setUp() public {
        token0 = new ERC20Mintable("Token A", "TKNA");
        token1 = new ERC20Mintable("Token B", "TKNB");
        pair = new UniswapV2Pair(address(token0), address(token1));

        token0.mint(10 ether, address(this));
        token1.mint(10 ether, address(this));
    }

    function testProvideInitialLiquidity() public {
        // Provide initial liquidity
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP

        assertEq(pair.balanceOf(address(this)), 1 ether - MINIMUM_LIQUIDITY);
        assertReserves(1 ether, 1 ether);
        assertEq(pair.totalSupply(), 1 ether);
    }

    function testMintWhenThereIsLiquidity() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 2 ether);

        pair.mint(); // + 2 LP

        assertEq(pair.balanceOf(address(this)), 3 ether - 1000);
        assertEq(pair.totalSupply(), 3 ether);
        assertReserves(3 ether, 3 ether);
    }

    function testMintUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP
        assertEq(pair.balanceOf(address(this)), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    function assertReserves(uint112 expectedReserve0, uint112 expectedReserve1) internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }
}
