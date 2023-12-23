// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

error IdenticalAddresses();
error PairExists();
error ZeroAddress();

/**
 * @title UniswapV2Factory
 * @author Borislav Stoyanov
 * @notice  This contract is used for creating UniswapV2Pair contracts and to keep track of them
 */
contract UniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    mapping(address token0 => mapping(address token1 => address pair)) public pairs;
    address[] public allPairs;

    function createPair(address _token0, address _token1) public returns (address pair) {
        if (_token0 == _token1) {
            revert IdenticalAddresses();
        }

        // sort token addresses to avoid duplicate pairs (token0, token1) vs (token1, token0)
        (address token0, address token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);

        if (token0 == address(0)) {
            revert ZeroAddress();
        }
        if (pairs[token0][token1] != address(0)) {
            revert PairExists();
        }

        // Creation code includes constructor code (not stored on the blokchain),
        // runtime bytecode - business logic (stored on the blockchain)
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        UniswapV2Pair(pair).initialize(token0, token1);

        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
