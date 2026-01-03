// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces.sol";
import "./Constants.sol";

interface ILLAMMAController {
    function liquidate_extended(
        address user,
        uint256 min_x,
        uint256 frac,
        bool use_eth,
        address callbacker,
        uint256[] calldata callback_args
    ) external;
    
    function tokens_to_liquidate(address user, uint256 frac) external view returns (uint256);
}

interface ICurveTriCrypto {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth,
        address receiver
    ) external payable returns (uint256);
    
    function get_dx(uint256 i, uint256 j, uint256 dy) external view returns (uint256);
}

interface ILLAMMACallback {
    function callback_liquidate(
        address user,
        uint256 stablecoins,
        uint256 collateral,
        uint256 debt,
        uint256[] calldata callback_args
    ) external returns (uint256[2] memory);
}

contract LiquidationContract is ILLAMMACallback {
    receive() external payable {}
    
    address private constant LLAMMA_CONTROLLER = 0xEdA215b7666936DEd834f76f3fBC6F323295110A;
    address private constant CURVE_POOL = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    
    IERC20 private constant CRV_TOKEN = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 private constant CRVUSD_TOKEN = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);

    constructor() {
        CRV_TOKEN.approve(CURVE_POOL, type(uint256).max);
        CRVUSD_TOKEN.approve(LLAMMA_CONTROLLER, type(uint256).max);
        CRVUSD_TOKEN.approve(CURVE_POOL, type(uint256).max);
    }

    function executeLiquidation() external {
        // liq 3% of pos 4 20k+ CRV
        uint256 liquidationPercent = 3e16; // 3% = 0.03
        
        //calc the crvusd
        uint256 requiredCrvUSD = ILLAMMAController(LLAMMA_CONTROLLER).tokens_to_liquidate(
            LIQUIDATABLE_USER,
            liquidationPercent
        );
        
        
        uint256[] memory callbackData = new uint256[](1);
        callbackData[0] = requiredCrvUSD;

        
        ILLAMMAController(LLAMMA_CONTROLLER).liquidate_extended(
            LIQUIDATABLE_USER,
            0, // No minimum CRV requirement
            liquidationPercent,
            false, // Don't use ETH
            address(this),
            callbackData
        );

        // Send profits to caller
        _sendProfitsToUser();
    }

    function callback_liquidate(
        address user,
        uint256 stablecoins,
        uint256 collateral,
        uint256 debt,
        uint256[] calldata callbackArgs
    ) external returns (uint256[2] memory) {
        require(msg.sender == LLAMMA_CONTROLLER, "Only LLAMMA can call");
        
        uint256 neededCrvUSD = callbackArgs[0];
        
        
        uint256 crvNeeded = ICurveTriCrypto(CURVE_POOL).get_dx(2, 0, neededCrvUSD);
        crvNeeded = crvNeeded * 101 / 100; // Add 1% buffer
        
        // conversion
        ICurveTriCrypto(CURVE_POOL).exchange(
            2, // CRV index
            0, // crvUSD index
            crvNeeded,
            0, // No minimum output
            false,
            address(this)
        );
        
        
        uint256 currentCrvUSD = CRVUSD_TOKEN.balanceOf(address(this));
        require(currentCrvUSD >= neededCrvUSD, "Not enough crvUSD after swap");
        
        
        return [currentCrvUSD, 0];
    }

    function _sendProfitsToUser() private {
        address user = msg.sender;
        
        // Send all CRV we have
        uint256 crvAmount = CRV_TOKEN.balanceOf(address(this));
        if (crvAmount > 0) {
            CRV_TOKEN.transfer(user, crvAmount);
        }
        
        // Convert remaining crvUSD back to CRV for profitmaxxing
        uint256 crvUSDAmount = CRVUSD_TOKEN.balanceOf(address(this));
        if (crvUSDAmount > 0) {
            try ICurveTriCrypto(CURVE_POOL).exchange(
                0, // crvUSD index
                2, // CRV index
                crvUSDAmount,
                0,
                false,
                user // Send directly to user
            ) {
                // Swap successful
            } catch {
                // If swap fails, just send crvUSD
                CRVUSD_TOKEN.transfer(user, crvUSDAmount);
            }
        }
    }
}
