# Before the Storm - Solution Writeup

## Challenge

Liquidate the exploiter's unhealthy Llamalend position and end up with at least 20,000 CRV tokens. We have no capital, so we need to use a flash loan approach.

## Solution

Instead of using a normal and traditional flash loan, we use flash liquidation. The liquidation protocol gives us CRV first, then we swap it to crvUSD and return it via a callback.

## How It Works

1. **Calculate what we need**: Use `tokens_to_liquidate()` to find out how much crvUSD is needed to liquidate 3% of the position.

2. **Start liquidation**: Call `liquidate_extended()` which:
   - Gives us CRV collateral immediately
   - Calls our `callback_liquidate()` function
   - Expects crvUSD in return

3. **In the callback**: 
   - Calculate how much CRV we need to swap (using `get_dx()` with 1% buffer for slippage)
   - Swap CRV to crvUSD via Curve TriCrypto pool
   - Return the crvUSD to complete the liquidation

4. **Maximize profit**: After liquidation, swap any remaining crvUSD back to CRV and send everything to the user.

##main points 

- **No external flash loan needed** - the liquidation itself provides the capital
- **3% liquidation** - enough to get 20k+ CRV after accounting for swaps
- **1% slippage buffer** - ensures we have enough CRV even with price movement
- **everything happens in one tx so fast**

## Result

At least 1% of position liquidated  
User receives 20,000+ CRV tokens  
All done in a single transaction
