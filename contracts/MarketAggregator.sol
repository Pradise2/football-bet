// ===============================================
// CONTRACT 7: MarketAggregator
// ===============================================

contract MarketAggregator {
    
    struct MarketSummary {
        address marketAddress;
        uint256 totalVolume;
        uint256 totalMarkets;
        uint256 activeMarkets;
        bool isActive;
    }
    
    struct GlobalStats {
        uint256 totalVolumeAllMarkets;
        uint256 totalMarketsAllContracts;
        uint256 totalActiveMarkets;
        uint256 totalUsers;
    }
    
    function getMarketSummaries(address[] calldata marketAddresses) 
        external view returns (MarketSummary[] memory) {
        
        MarketSummary[] memory summaries = new MarketSummary[](marketAddresses.length);
        
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            try PredictionMarket(marketAddresses[i]).getPlatformStats() 
                returns (uint256 volume, uint256 total, uint256 users, uint256 active) {
                
                summaries[i] = MarketSummary({
                    marketAddress: marketAddresses[i],
                    totalVolume: volume,
                    totalMarkets: total,
                    activeMarkets: active,
                    isActive: true
                });
            } catch {
                summaries[i] = MarketSummary({
                    marketAddress: marketAddresses[i],
                    totalVolume: 0,
                    totalMarkets: 0,
                    activeMarkets: 0,
                    isActive: false
                });
            }
        }
        
        return summaries;
    }
    
    function getGlobalStats(address[] calldata marketAddresses) 
        external view returns (GlobalStats memory) {
        
        uint256 totalVolume = 0;
        uint256 totalMarkets = 0;
        uint256 totalActive = 0;
        uint256 totalUsers = 0;
        
        for (uint256 i = 0; i < marketAddresses.length; i++) {
            try PredictionMarket(marketAddresses[i]).getPlatformStats() 
                returns (uint256 volume, uint256 markets, uint256 users, uint256 active) {
                
                totalVolume += volume;
                totalMarkets += markets;
                totalActive += active;
                totalUsers += users;
            } catch {
                continue;
            }
        }
        
        return GlobalStats({
            totalVolumeAllMarkets: totalVolume,
            totalMarketsAllContracts: totalMarkets,
            totalActiveMarkets: totalActive,
            totalUsers: totalUsers
        });
    }
}