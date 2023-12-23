// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Factory, IdenticalAddresses, PairExists, ZeroAddress} from "../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;
    ERC20Mintable token0;
    ERC20Mintable token1;

    function setUp() public {
        factory = new UniswapV2Factory();
        token0 = new ERC20Mintable("BoringToken", "BRT");
        token1 = new ERC20Mintable("NotBoringToken", "NBRT");
    }

    function testCreatePair() public {
        address pairAddress = factory.createPair(address(token1), address(token0));

        UniswapV2Pair pair = UniswapV2Pair(pairAddress);

        assertEq(pair.token0(), address(token0));
        assertEq(pair.token1(), address(token1));
    }

    function testCreatePairZeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        factory.createPair(address(token0), address(0));
    }

    function testCreatePairExistingPair() public {
        factory.createPair(address(token0), address(token1));
        vm.expectRevert(PairExists.selector);
        factory.createPair(address(token0), address(token1));
    }

    function testCreatePairIdenticalAddresses() public {
        vm.expectRevert(IdenticalAddresses.selector);
        factory.createPair(address(token0), address(token0));
    }
}
