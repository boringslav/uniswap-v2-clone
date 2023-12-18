// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "./libraries/Math.sol";

error InsufficientLiquidityMinted();

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

contract UniswapV2Pair is ERC20, Math {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);

    uint256 constant MINIMUM_LIQUIDITY = 1000; // 1e15

    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;

    constructor(address _token0, address _token1) ERC20("Uniswap V2 Pair", "Pair", 18) {
        token0 = _token0;
        token1 = _token1;
    }

    function mint() public {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 liquidity;

        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amount0 * totalSupply) / _reserve0, (amount1 * totalSupply) / _reserve1);
        }

        if (liquidity <= 0) revert InsufficientLiquidityMinted();

        _mint(msg.sender, liquidity);

        _update(balance0, balance1);

        emit Mint(msg.sender, amount0, amount1);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }
}
