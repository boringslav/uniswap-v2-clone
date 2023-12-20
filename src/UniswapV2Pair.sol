// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "./libraries/Math.sol";

error InsufficientLiquidityMinted();
error TransferFailed();
error InsufficientLiquidityBurned();

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

contract UniswapV2Pair is ERC20, Math {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint112 reserve0, uint112 reserve1);

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
        // Measure the amount of tokens that are sent as part of the transaction
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 liquidity;

        // If the pool empty, that is, liquidity tokens have a total supply of zero, then no liquidity has been provided yet.
        //
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            //The fact that the user will get the worse of the two ratios (amount0 / _reserve0 or amount1 / _reserve1) they provide
            //incentivizes them to increase the supply of token0 and token1 without changing the ratio of token0 and token1.
            //If we took the maximum of the two ratios, someone could supply one additional token1 (at a cost of $100) and raise the pool value to $300.
            //They’ve increase the pool value by 50%. However, under the maximum calculation,
            //they would get minted 1 LP tokens, meaning they own 50% of the supply of the LP tokens,
            //since the total circulating supply is now 2 LP tokens.
            //Now they control 50% of the $300 pool (worth $150) by only depositing $100 of value.
            //This is clearly stealing from other LP providers.
            liquidity = Math.min((amount0 * totalSupply) / _reserve0, (amount1 * totalSupply) / _reserve1);
        }

        if (liquidity <= 0) revert InsufficientLiquidityMinted();

        _mint(msg.sender, liquidity);

        _update(balance0, balance1);

        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     *  @notice Burn liquidity tokens to withdraw the underlying tokens
     *  @dev The amount of underlying tokens that can be withdrawn is proportional to the amount of liquidity tokens burned
     *  UniswapV2 doesn't support partial burning,
     *  so the amount of liquidity tokens burned must be equal to the total amount of liquidity tokens held by the user
     */
    function burn() public {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[msg.sender];

        uint256 amount0 = (liquidity * balance0) / totalSupply;
        uint256 amount1 = (liquidity * balance1) / totalSupply;

        if (amount0 <= 0 || amount1 <= 0) revert InsufficientLiquidityBurned();

        _burn(msg.sender, liquidity);

        _safeTransfer(token0, msg.sender, amount0);
        _safeTransfer(token1, msg.sender, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        _update(balance0, balance1);

        emit Burn(msg.sender, amount0, amount1);
    }

    /**
     * @notice Update the reserves of token0 and token1
     * @param balance0  The amount of token0 that is in the contract
     * @param balance1  The amount of token1 that is in the contract
     */
    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        emit Sync(reserve0, reserve1);
    }

    /**
     * @notice Transfer tokens safely
     * @param token The address of the token to transfer
     * @param to    The address to transfer the tokens to
     * @param value The amount of tokens to transfer
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    /**
     * @notice Get the reserves of token0 and token1
     * @return reserve0 The amount of token0 that is in the contract
     * @return reserve1 The amount of token1 that is in the contract
     * @return 0        The current block timestamp
     */
    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }
}
