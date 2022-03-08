// solhint-disable no-unused-vars
// SPDX-License-Identifier:MIT

pragma solidity =0.8.11;

//  libraries
import { Address } from "@openzeppelin/contracts-0.8.x/utils/Address.sol";

//  helper contracts
import { ERC20 } from "@openzeppelin/contracts-0.8.x/token/ERC20/ERC20.sol";
import { AdapterModifiersBase } from "../../utils/AdapterModifiersBase.sol";

//  interfaces
import { IAdapter } from "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapter.sol";
import "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapterInvestLimit.sol";
import { ICurveMetapoolSwap } from "@optyfi/defi-legos/ethereum/curve/contracts/ICurveMetapoolSwap.sol";
import { ICurveMetapoolFactory } from "@optyfi/defi-legos/ethereum/curve/contracts/ICurveMetapoolFactory.sol";

/**
 * @title Adapter for Curve Metapool Swap pools
 * @author Opty.fi
 * @dev Abstraction layer to Curve's Metapool swap pools
 *      Note 1 : In this adapter, a swap pool is defined as a single-sided liquidity pool
 *      Note 2 : In this adapter, lp token can be redemeed into more than one underlying token
 */
contract CurveMetapoolSwapAdapter is IAdapter, IAdapterInvestLimit, AdapterModifiersBase {
    using Address for address;

    /** @notice max deposit value datatypes */
    MaxExposure public maxDepositProtocolMode;

    /** @notice  Curve Metapool Factory */
    address public constant METAPOOL_FACTORY = address(0x0959158b6040D32d04c301A72CBFD6b39E21c9AE);

    /** @notice HBTC token contract address */
    address public constant HBTC = address(0x0316EB71485b0Ab14103307bf65a021042c6d380);

    /** @notice max deposit's default value in percentage */
    uint256 public maxDepositProtocolPct; // basis points

    /** @notice Maps liquidityPool to absolute max deposit value in underlying */
    mapping(address => uint256) public maxDepositAmount;

    /** @notice  Maps liquidityPool to max deposit value in percentage */
    mapping(address => uint256) public maxDepositPoolPct; // basis points

    /**
     * @dev mapp coins and tokens to curve deposit pool
     */
    constructor(address _registry) AdapterModifiersBase(_registry) {
        maxDepositProtocolPct = uint256(10000); // 100% (basis points)
        maxDepositProtocolMode = MaxExposure.Pct;
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositPoolPct(address _swapPool, uint256 _maxDepositPoolPct) external override onlyRiskOperator {
        maxDepositPoolPct[_swapPool] = _maxDepositPoolPct;
        emit LogMaxDepositPoolPct(maxDepositPoolPct[_swapPool], msg.sender);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositAmount(
        address _swapPool,
        address,
        uint256 _maxDepositAmount
    ) external override onlyRiskOperator {
        // Note : use 18 as decimals for USD, BTC and ETH
        maxDepositAmount[_swapPool] = _maxDepositAmount;
        emit LogMaxDepositAmount(maxDepositAmount[_swapPool], msg.sender);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositProtocolMode(MaxExposure _mode) public override onlyRiskOperator {
        maxDepositProtocolMode = _mode;
        emit LogMaxDepositProtocolMode(maxDepositProtocolMode, msg.sender);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositProtocolPct(uint256 _maxDepositProtocolPct) public override onlyRiskOperator {
        maxDepositProtocolPct = _maxDepositProtocolPct;
        emit LogMaxDepositProtocolPct(maxDepositProtocolPct, msg.sender);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getPoolValue(address _swapPool, address) public view override returns (uint256) {
        uint256 _virtualPrice = ICurveMetapoolSwap(_swapPool).get_virtual_price();
        uint256 _totalSupply = ERC20(getLiquidityPoolToken(address(0), _swapPool)).totalSupply();
        // the pool value will be in USD for US dollar stablecoin pools
        // the pool value will be in BTC for BTC pools
        return (_virtualPrice * _totalSupply) / (10**18);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getDepositAllCodes(
        address payable _vault,
        address _underlyingToken,
        address _swapPool
    ) public view override returns (bytes[] memory) {
        uint256 _amount = ERC20(_underlyingToken).balanceOf(_vault);
        return _getDepositCode(_vault, _underlyingToken, _swapPool, _amount);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getWithdrawAllCodes(
        address payable _vault,
        address _underlyingToken,
        address _swapPool
    ) public view override returns (bytes[] memory) {
        uint256 _amount = getLiquidityPoolTokenBalance(_vault, address(0), _swapPool);
        return getWithdrawSomeCodes(_vault, _underlyingToken, _swapPool, _amount);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getUnderlyingTokens(address _swapPool, address)
        public
        view
        override
        returns (address[] memory _underlyingTokens)
    {
        address _curveRegistry = _getCurveRegistry();
        address[2] memory _underlyingCoins = _getUnderlyingTokens(_swapPool, _curveRegistry);
        uint256 _nCoins = _getNCoins(_swapPool, _curveRegistry);
        _underlyingTokens = new address[](_nCoins);
        for (uint256 _i = 0; _i < _nCoins; _i++) {
            _underlyingTokens[_i] = _underlyingCoins[_i];
        }
    }

    /**
     * @inheritdoc IAdapter
     */
    function calculateAmountInLPToken(
        address _underlyingToken,
        address _swapPool,
        uint256 _underlyingTokenAmount
    ) public view override returns (uint256 _amount) {
        address _curveRegistry = _getCurveRegistry();
        uint256 _nCoins = _getNCoins(_swapPool, _curveRegistry);
        uint256[2] memory _amounts;
        address[2] memory _underlyingTokens = _getUnderlyingTokens(_swapPool, _curveRegistry);
        for (uint256 _i = 0; _i < _nCoins; _i++) {
            if (_underlyingTokens[_i] == _underlyingToken) {
                _amounts[_i] = _underlyingTokenAmount;
            }
        }
        _amount = ICurveMetapoolSwap(_swapPool).calc_token_amount(_amounts, true);
    }

    /**
     * @inheritdoc IAdapter
     */
    function calculateRedeemableLPTokenAmount(
        address payable _vault,
        address _underlyingToken,
        address _swapPool,
        uint256 _redeemAmount
    ) public view override returns (uint256) {
        uint256 _liquidityPoolTokenBalance = getLiquidityPoolTokenBalance(_vault, address(0), _swapPool);
        uint256 _balanceInToken = getAllAmountInToken(_vault, _underlyingToken, _swapPool);
        // can have unintentional rounding errors
        return ((_liquidityPoolTokenBalance * _redeemAmount) / (_balanceInToken)) + uint256(1);
    }

    /**
     * @inheritdoc IAdapter
     */
    function isRedeemableAmountSufficient(
        address payable _vault,
        address _underlyingToken,
        address _swapPool,
        uint256 _redeemAmount
    ) public view override returns (bool) {
        uint256 _balanceInToken = getAllAmountInToken(_vault, _underlyingToken, _swapPool);
        return _balanceInToken >= _redeemAmount;
    }

    /**
     * @inheritdoc IAdapter
     */
    function canStake(address) public pure override returns (bool) {
        return false;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getDepositSomeCodes(
        address payable _vault,
        address _underlyingToken,
        address _swapPool,
        uint256 _amount
    ) public view override returns (bytes[] memory) {
        return _getDepositCode(_vault, _underlyingToken, _swapPool, _amount);
    }

    /**
     * @inheritdoc IAdapter
     * @dev Note : swap pools of compound,usdt,pax,y,susd and busd
     *             does not have remove_liquidity_one_coin function
     */
    function getWithdrawSomeCodes(
        address payable,
        address _underlyingToken,
        address _swapPool,
        uint256 _amount
    ) public view override returns (bytes[] memory _codes) {
        if (_amount > 0) {
            address _liquidityPoolToken = getLiquidityPoolToken(address(0), _swapPool);
            _codes = new bytes[](3);
            _codes[0] = abi.encode(
                _liquidityPoolToken,
                abi.encodeWithSignature("approve(address,uint256)", _swapPool, uint256(0))
            );
            _codes[1] = abi.encode(
                _liquidityPoolToken,
                abi.encodeWithSignature("approve(address,uint256)", _swapPool, _amount)
            );

            _codes[2] = abi.encode(
                _swapPool,
                // solhint-disable-next-line max-line-length
                abi.encodeWithSignature(
                    "remove_liquidity_one_coin(uint256,int128,uint256)",
                    _amount,
                    _getTokenIndex(_swapPool, _underlyingToken),
                    (getSomeAmountInToken(_underlyingToken, _swapPool, _amount) * uint256(95)) / uint256(100)
                )
            );
        }
    }

    /**
     * @inheritdoc IAdapter
     */
    function getLiquidityPoolToken(address, address _swapPool) public pure override returns (address) {
        return _swapPool;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getAllAmountInToken(
        address payable _vault,
        address _underlyingToken,
        address _swapPool
    ) public view override returns (uint256) {
        uint256 _liquidityPoolTokenAmount = getLiquidityPoolTokenBalance(_vault, address(0), _swapPool);
        return getSomeAmountInToken(_underlyingToken, _swapPool, _liquidityPoolTokenAmount);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getLiquidityPoolTokenBalance(
        address payable _vault,
        address,
        address _swapPool
    ) public view override returns (uint256) {
        return ERC20(getLiquidityPoolToken(address(0), _swapPool)).balanceOf(_vault);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getSomeAmountInToken(
        address _underlyingToken,
        address _swapPool,
        uint256 _liquidityPoolTokenAmount
    ) public view override returns (uint256) {
        if (_liquidityPoolTokenAmount > 0) {
            return
                ICurveMetapoolSwap(_swapPool).calc_withdraw_one_coin(
                    _liquidityPoolTokenAmount,
                    _getTokenIndex(_swapPool, _underlyingToken)
                );
        }
        return 0;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getRewardToken(address) public pure override returns (address) {
        return address(0);
    }

    /* solhint-enable no-empty-blocks */

    /**
     * @dev This function composes the configuration required to construct fuction calls
     * @param _underlyingToken address of the underlying asset
     * @param _swapPool swap pool address
     * @param _amount amount in underlying token
     * @return _underlyingTokenIndex index of _underlyingToken
     * @return _nCoins number of underlying tokens in swap pool
     * @return _underlyingTokens underlying tokens in a swap pool
     * @return _amounts value in an underlying token for each underlying token
     * @return _codeLength number of function call required for deposit
     */
    function _getDepositCodeConfig(
        address _underlyingToken,
        address _swapPool,
        uint256 _amount
    )
        internal
        view
        returns (
            int128 _underlyingTokenIndex,
            uint256 _nCoins,
            address[2] memory _underlyingTokens,
            uint256[] memory _amounts,
            uint256 _codeLength,
            uint256 _minAmount
        )
    {
        address _curveRegistry = _getCurveRegistry();
        _nCoins = _getNCoins(_swapPool, _curveRegistry);
        _underlyingTokens = _getUnderlyingTokens(_swapPool, _curveRegistry);
        _underlyingTokenIndex = _getTokenIndex(_swapPool, _underlyingToken);
        _amounts = new uint256[](_nCoins);
        _codeLength = 1;
        for (uint256 _i = 0; _i < _nCoins; _i++) {
            if (_underlyingTokens[_i] == _underlyingToken) {
                _amounts[_i] = _getDepositAmount(_swapPool, _underlyingToken, _amount);
                uint256 _decimals = ERC20(_underlyingToken).decimals();
                _minAmount =
                    (_amounts[_i] * (uint256(10)**(uint256(36) - _decimals)) * uint256(95)) /
                    (ICurveMetapoolSwap(_swapPool).get_virtual_price() * uint256(100));
                if (_amounts[_i] > 0) {
                    if (_underlyingTokens[_i] == HBTC) {
                        _codeLength++;
                    } else {
                        _codeLength += 2;
                    }
                }
            }
        }
    }

    /**
     * @dev This functions returns the token index for a underlying token
     * @param _underlyingToken address of the underlying asset
     * @param _swapPool swap pool address
     * @return _tokenIndex index of coin in swap pool
     */
    function _getTokenIndex(address _swapPool, address _underlyingToken) internal view returns (int128) {
        address[2] memory _underlyingTokens = _getUnderlyingTokens(_swapPool, _getCurveRegistry());
        for (uint256 _i = 0; _i < _underlyingTokens.length; _i++) {
            if (_underlyingTokens[_i] == _underlyingToken) {
                return int128(uint128(_i));
            }
        }
        return int128(0);
    }

    /**
     * @dev This functions composes the function calls to deposit asset into deposit pool
     * @param _underlyingToken address of the underlying asset
     * @param _swapPool swap pool address
     * @param _amount the amount in underlying token
     * @return _codes bytes array of function calls to be executed from vault
     */
    function _getDepositCode(
        address payable,
        address _underlyingToken,
        address _swapPool,
        uint256 _amount
    ) internal view returns (bytes[] memory _codes) {
        (
            ,
            uint256 _nCoins,
            address[2] memory _underlyingTokens,
            uint256[] memory _amounts,
            uint256 _codeLength,
            uint256 _minAmount
        ) = _getDepositCodeConfig(_underlyingToken, _swapPool, _amount);
        if (_codeLength > 1) {
            _codes = new bytes[](_codeLength);
            uint256 _j = 0;
            for (uint256 i = 0; i < _nCoins; i++) {
                if (_amounts[i] > 0) {
                    if (_underlyingTokens[i] == HBTC) {
                        _codes[_j++] = abi.encode(
                            _underlyingTokens[i],
                            abi.encodeWithSignature("approve(address,uint256)", _swapPool, _amounts[i])
                        );
                    } else {
                        _codes[_j++] = abi.encode(
                            _underlyingTokens[i],
                            abi.encodeWithSignature("approve(address,uint256)", _swapPool, uint256(0))
                        );
                        _codes[_j++] = abi.encode(
                            _underlyingTokens[i],
                            abi.encodeWithSignature("approve(address,uint256)", _swapPool, _amounts[i])
                        );
                    }
                }
            }
            if (_nCoins == uint256(2)) {
                uint256[2] memory _depositAmounts = [_amounts[0], _amounts[1]];
                _codes[_j] = abi.encode(
                    _swapPool,
                    abi.encodeWithSignature("add_liquidity(uint256[2],uint256)", _depositAmounts, _minAmount)
                );
            } else if (_nCoins == uint256(3)) {
                uint256[3] memory _depositAmounts = [_amounts[0], _amounts[1], _amounts[2]];
                _codes[_j] = abi.encode(
                    _swapPool,
                    abi.encodeWithSignature("add_liquidity(uint256[3],uint256)", _depositAmounts, _minAmount)
                );
            } else if (_nCoins == uint256(4)) {
                uint256[4] memory _depositAmounts = [_amounts[0], _amounts[1], _amounts[2], _amounts[3]];
                _codes[_j] = abi.encode(
                    _swapPool,
                    abi.encodeWithSignature("add_liquidity(uint256[4],uint256)", _depositAmounts, _minAmount)
                );
            }
        }
    }

    /**
     * @dev Get the underlying tokens within a swap pool.
     *      Note: For pools using lending, these are the
     *            wrapped coin addresses
     * @param _swapPool the swap pool address
     * @param _curveRegistry the address of the Curve registry
     * @return list of coin addresses
     */
    function _getUnderlyingTokens(address _swapPool, address _curveRegistry) internal view returns (address[2] memory) {
        return ICurveMetapoolFactory(_curveRegistry).get_coins(_swapPool);
    }

    /**
     * @dev Get the address of the main registry contract
     * @return Address of the main registry contract
     */
    function _getCurveRegistry() internal pure returns (address) {
        return METAPOOL_FACTORY;
    }

    /**
     * @dev Get number of underlying tokens in a liquidity pool
     * @param _swapPool swap pool address associated with liquidity pool
     * @param _curveRegistry address of the main registry contract
     * @return  _nCoins Number of underlying tokens
     */
    function _getNCoins(address _swapPool, address _curveRegistry) internal view returns (uint256 _nCoins) {
        (_nCoins, ) = ICurveMetapoolFactory(_curveRegistry).get_n_coins(_swapPool);
    }

    /**
     * @dev Get the final value of amount in underlying token to be deposited
     * @param _swapPool swap pool address
     * @param _underlyingToken underlying token address
     * @param _amount amount in underlying token
     * @return amount in underlying token to be deposited affected by investment limitation
     */
    function _getDepositAmount(
        address _swapPool,
        address _underlyingToken,
        uint256 _amount
    ) internal view returns (uint256) {
        return
            maxDepositProtocolMode == MaxExposure.Pct
                ? _getMaxDepositAmountPct(_swapPool, _underlyingToken, _amount)
                : _getMaxDepositAmount(_swapPool, _underlyingToken, _amount);
    }

    /**
     * @dev Gets the maximum amount in underlying token limited by percentage
     * @param _swapPool swap pool address
     * @param _underlyingToken underlying token address
     * @param _amount amount in underlying token
     * @return  amount in underlying token to be deposited affected by
     *          investment limit in percentage
     */
    function _getMaxDepositAmountPct(
        address _swapPool,
        address _underlyingToken,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 _poolValue = getPoolValue(_swapPool, address(0));
        uint256 _poolPct = maxDepositPoolPct[_swapPool];
        uint256 _decimals = ERC20(_underlyingToken).decimals();
        uint256 _actualAmount = _amount * (uint256(10)**(uint256(18) - _decimals));
        uint256 _limit = _poolPct == 0
            ? (_poolValue * maxDepositProtocolPct) / (10000)
            : (_poolValue * _poolPct) / (10000);
        return _actualAmount > _limit ? _limit / (10**(uint256(18) - _decimals)) : _amount;
    }

    /**
     * @dev Gets the maximum amount in underlying token affected by investment
     *      limit set for swap pool in amount
     * @param _swapPool swap pool address
     * @param _underlyingToken underlying token address
     * @param _amount amount in underlying token
     * @return amount in underlying token to be deposited affected by
     *         investment limit set for swap pool in amount
     */
    function _getMaxDepositAmount(
        address _swapPool,
        address _underlyingToken,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 _decimals = ERC20(_underlyingToken).decimals();
        uint256 _maxAmount = maxDepositAmount[_swapPool] / (10**(uint256(18) - _decimals));
        return _amount > _maxAmount ? _maxAmount : _amount;
    }
}
