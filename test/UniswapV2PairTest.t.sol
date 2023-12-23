// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {UniswapV2Pair, InsufficientOutputAmount, InvalidK} from "../src/UniswapV2Pair.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract UniswapV2PairTest is Test {
    ERC20Mintable public token0;
    ERC20Mintable public token1;
    UniswapV2Pair public pair;

    TestUser public testUser = new TestUser();
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

    function testBurn() public {
        // Provide initial liquidity
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint();
        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1000, 1000);
        assertEq(pair.totalSupply(), 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
        assertEq(token1.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
    }

    function testBurnUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint();

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP

        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1500, 1000);
        assertEq(pair.totalSupply(), 1000);
        // Here additional 500 wei is lost from token0.
        // This is the punishment price for price manipulaiton.
        assertEq(token0.balanceOf(address(this)), 10 ether - 1500);
        assertEq(token1.balanceOf(address(this)), 10 ether - MINIMUM_LIQUIDITY);
    }

    function testBurnUnbalancedDifferentUsers() public {
        testUser.provideLiquidity(address(pair), address(token0), address(token1), 1 ether, 1 ether);

        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.balanceOf(address(testUser)), 1 ether - 1000);
        assertEq(pair.totalSupply(), 1 ether);

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP

        pair.burn();

        // this user is penalized for providing unbalanced liquidity
        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1.5 ether, 1 ether);
        assertEq(pair.totalSupply(), 1 ether);
        assertEq(token0.balanceOf(address(this)), 10 ether - 0.5 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);
    }

    function testSwap() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        // transfer the token that we want to trade in
        token0.transfer(address(pair), 0.1 ether);
        // swap 0.1 ether of token0 to token1 (0.18 ether)
        pair.swap(0, 0.18 ether, address(this));

        assertEq(token0.balanceOf(address(this)), 10 ether - 1 ether - 0.1 ether, "unexpected token0 balance");
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether + 0.18 ether, "unexpected token1 balance");
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.18 ether);
    }

    function testSwapReversedDirection() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        // transfer the token that we want to trade in
        token1.transfer(address(pair), 0.2 ether);
        pair.swap(0.09 ether, 0, address(this));

        assertEq(token0.balanceOf(address(this)), 10 ether - 1 ether + 0.09 ether, "unexpected token0 balance");
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether - 0.2 ether, "unexpected token1 balance");
        assertReserves(1 ether - 0.09 ether, 2 ether + 0.2 ether);
    }

    function testSwapBidirectional() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        // transfer the tokens that we want to trade in
        token0.transfer(address(pair), 0.1 ether);
        token1.transfer(address(pair), 0.2 ether);

        pair.swap(0.09 ether, 0.18 ether, address(this));

        assertEq(token0.balanceOf(address(this)), 10 ether - 1 ether - 0.01 ether, "unexpected token0 balance");
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether - 0.02 ether, "unexpected token1 balance");
        assertReserves(1 ether + 0.01 ether, 2 ether + 0.02 ether);
    }

    function testSwapZeroOut() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        vm.expectRevert(InsufficientOutputAmount.selector);
        pair.swap(0, 0, address(this));
    }

    function testSwapUnderpriced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.09 ether, address(this));

        assertEq(token0.balanceOf(address(this)), 10 ether - 1 ether - 0.1 ether, "unexpected token0 balance");
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether + 0.09 ether, "unexpected token1 balance");
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.09 ether);
    }

    function testSwapOverpriced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.mint();

        token0.transfer(address(pair), 0.1 ether);

        vm.expectRevert(InvalidK.selector);
        pair.swap(0, 0.36 ether, address(this));

        assertEq(token0.balanceOf(address(this)), 10 ether - 1 ether - 0.1 ether, "unexpected token0 balance");
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether, "unexpected token1 balance");
        assertReserves(1 ether, 2 ether);
    }

    function assertReserves(uint112 expectedReserve0, uint112 expectedReserve1) internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }
}

contract TestUser {
    function provideLiquidity(
        address pairAddress_,
        address token0Address_,
        address token1Address_,
        uint256 amount0_,
        uint256 amount1_
    ) public {
        ERC20(token0Address_).transfer(pairAddress_, amount0_);
        ERC20(token1Address_).transfer(pairAddress_, amount1_);

        UniswapV2Pair(pairAddress_).mint();
    }

    function withdrawLiquidity(address pairAddress_) public {
        UniswapV2Pair(pairAddress_).burn();
    }
}
