// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "./libraries/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";

error InsufficientLiquidityMinted();
error TransferFailed();
error InsufficientLiquidityBurned();
error InsufficientOutputAmount();
error InsufficientLiquidity();
error InvalidK();
error BalanceOverflow();
error AlreadyInitialized();

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

/**
 * @title UniswapV2Pair
 * @author  Borislav Stoyanov
 */
contract UniswapV2Pair is ERC20, Math {
    using UQ112x112 for uint224;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Swap(address indexed sender, uint256 amount0Out, uint256 amount1Out, address to);
    event Sync(uint112 reserve0, uint112 reserve1);

    uint256 constant MINIMUM_LIQUIDITY = 1000; // 1e15

    address public token0;
    address public token1;

    // reservers and blockTiempstampLast are stored in one storage slot
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    constructor(address _token0, address _token1) ERC20("Uniswap V2 Pair", "Pair", 18) {
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Initializes the contract (sets the addresses of the tokens)
     * @param token0_  The address of the first token
     * @param token1_  The address of the second token
     * @dev This function can only be called once. It is called by the UniswapV2Factory contract
     */
    function initialize(address token0_, address token1_) public {
        if (token0 != address(0) || token1 != address(0)) {
            revert AlreadyInitialized();
        }

        token0 = token0_;
        token1 = token1_;
    }

    /**
     * @notice The swap function doesn't enforce the direction of the swap.
     * Caller can specify either of the amounts or both, and the function will perform the necessary checks
     * @param amount0Out amount of token0 to swap
     * @param amount1Out  amount of token1 to swap
     * @param to the address to send the swapped tokens to
     * @dev Swap fees are not implemented
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to) public {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();

        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        // Check if there are enough of reserves to perform the swap
        if (amount0Out > reserve0_ || amount1Out > reserve1_) {
            revert InsufficientLiquidity();
        }
        // Calculate the token balances
        // it’s expected that the caller has sent tokens they want to trade in to this contract
        uint256 balance0 = IERC20(token0).balanceOf(address(this)) - amount0Out;
        uint256 balance1 = IERC20(token1).balanceOf(address(this)) - amount1Out;

        // We expect that this contract token balances are different
        // than its reserves and we need to ensure that their product
        // is equal or greater than the product of current reserves.
        if (balance0 * balance1 < uint256(reserve0_) * uint256(reserve1_)) {
            revert InvalidK();
        }

        // Update the reserves
        _update(balance0, balance1, reserve0_, reserve1_);
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out); // optimistically transfer tokens

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    /**
     * @notice Mint liquidity tokens to provide liquidity
     * @dev The amount of liquidity tokens minted is proportional to the amount of tokens provided
     */
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

        _update(balance0, balance1, _reserve0, _reserve1);

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

        _update(balance0, balance1, reserve0, reserve1);

        emit Burn(msg.sender, amount0, amount1);
    }

    /**
     * @notice Update the reserves of token0 and token1
     * @param balance0  The amount of token0 that is in the contract
     * @param balance1  The amount of token1 that is in the contract
     */
    function _update(uint256 balance0, uint256 balance1, uint112 reserve0_, uint112 reserve1_) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert BalanceOverflow();
        }

        unchecked {
            uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;

            if (timeElapsed > 0 && reserve0_ > 0 && reserve1_ > 0) {
                price0CumulativeLast += uint256(UQ112x112.encode(reserve1_).uqdiv(reserve0_)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(reserve0_).uqdiv(reserve1_)) * timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }
    /**
     * @notice Transfer tokens safely
     * @param token The address of the token to transfer
     * @param to    The address to transfer the tokens to
     * @param value The amount of tokens to transfer
     * @dev This is used because some tokens don't return a boolean value on success
     * @dev We check the transfer result to make sure the transfer succeeded
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
