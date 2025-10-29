-- {"query": "7872.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2069} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as RepRank,
        ROW_NUMBER() OVER (PARTITION BY CASE WHEN u.Reputation >= 10000 THEN 'High' ELSE 'Low' END ORDER BY u.CreationDate) as CreatedOrder
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' 
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostRankings AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScorePerType,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.ViewCount, 1) OVER (ORDER BY p.CreationDate) as NextViews,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
            ELSE 'Medium'
        END as ScoreCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
            0
        ) as CommentCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as Upvotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as Downvotes
    FROM Posts p
    WHERE p.CreationDate >= '2019-01-01' 
    AND p.PostTypeId IN (1, 2)
),
ComplexUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.RepRank,
        uas.CreatedOrder,
        CASE 
            WHEN uas.Questions > 100 AND uas.Answers > 500 THEN 'Power User'
            WHEN uas.Questions > 50 AND uas.Answers > 100 THEN 'Active Contributor'
            WHEN uas.Badges >= 50 THEN 'Badge Hunter'
            ELSE 'Regular User'
        END as UserCategory,
        CASE 
            WHEN uas.Reputation >= 100000 THEN 'Elite'
            WHEN uas.Reputation >= 50000 THEN 'Veteran'
            WHEN uas.Reputation >= 10000 THEN 'Experienced'
            ELSE 'Beginner'
        END as RepTier,
        ROW_NUMBER() OVER (PARTITION BY uas.RepTier ORDER BY uas.Reputation DESC) as TierRank,
        NTH_VALUE(uas.DisplayName, 1) OVER (PARTITION BY uas.RepTier ORDER BY uas.Reputation DESC) as TopRepUserInTier
    FROM UserActivityStats uas
),
DetailedPostAnalysis AS (
    SELECT 
        pra.PostId,
        pra.Title,
        pra.Score,
        pra.ViewCount,
        pra.CreationDate,
        pra.OwnerUserId,
        pra.PostTypeId,
        pra.ScoreRank,
        pra.ViewPercentile,
        pra.AvgScorePerType,
        pra.PrevScore,
        pra.NextViews,
        pra.ScoreCategory,
        pra.CommentCount,
        pra.Upvotes,
        pra.Downvotes,
        CASE 
            WHEN pra.Score > pra.AvgScorePerType THEN 'Above Average'
            WHEN pra.Score < pra.AvgScorePerType THEN 'Below Average'
            ELSE 'Average'
        END as PerformanceCategory,
        CASE 
            WHEN pra.ViewCount > 1000 THEN 'High Views'
            WHEN pra.ViewCount > 100 THEN 'Medium Views'
            WHEN pra.ViewCount > 10 THEN 'Low Views'
            ELSE 'Very Low Views'
        END as ViewCategory,
        CASE 
            WHEN pra.Upvotes - pra.Downvotes > 50 THEN 'Popular'
            WHEN pra.Upvotes - pra.Downvotes > 10 THEN 'Moderately Popular'
            WHEN pra.Upvotes - pra.Downvotes < -10 THEN 'Controversial'
            ELSE 'Neutral'
        END as PopularityRating,
        ROW_NUMBER() OVER (ORDER BY pra.ViewCount DESC) as ViewRank
    FROM PostRankings pra
),
CombinedAnalysis AS (
    SELECT 
        dua.UserId,
        dua.DisplayName,
        dua.Reputation,
        dua.TotalPosts,
        dua.Questions,
        dua.Answers,
        dua.Comments,
        dua.Badges,
        dua.LastPostDate,
        dua.RepRank,
        dua.CreatedOrder,
        dua.UserCategory,
        dua.RepTier,
        dua.TierRank,
        dua.TopRepUserInTier,
        dpa.PostId,
        dpa.Title,
        dpa.Score,
        dpa.ViewCount,
        dpa.CreationDate as PostCreationDate,
        dpa.PostTypeId,
        dpa.ScoreRank,
        dpa.ViewPercentile,
        dpa.AvgScorePerType,
        dpa.PrevScore,
        dpa.NextViews,
        dpa.ScoreCategory,
        dpa.CommentCount,
        dpa.Upvotes,
        dpa.Downvotes,
        dpa.PerformanceCategory,
        dpa.ViewCategory,
        dpa.PopularityRating,
        dpa.ViewRank,
        DATEDIFF('day', dua.LastPostDate, dpa.CreationDate) as DaysSinceLastPost,
        CASE 
            WHEN dua.Reputation >= 10000 AND dpa.Score >= 100 THEN 'High Impact Post'
            WHEN dua.Reputation >= 1000 AND dpa.Score >= 50 THEN 'Moderate Impact Post'
            ELSE 'Standard Post'
        END as ImpactLevel
    FROM ComplexUserAnalysis dua
    FULL OUTER JOIN DetailedPostAnalysis dpa ON dua.UserId = dpa.OwnerUserId
    WHERE dua.UserId IS NOT NULL OR dpa.PostId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.Comments,
    ca.Badges,
    ca.LastPostDate,
    ca.RepRank,
    ca.CreatedOrder,
    ca.UserCategory,
    ca.RepTier,
    ca.TierRank,
    ca.TopRepUserInTier,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.PostCreationDate,
    ca.PostTypeId,
    ca.ScoreRank,
    ca.ViewPercentile,
    ca.AvgScorePerType,
    ca.PrevScore,
    ca.NextViews,
    ca.ScoreCategory,
    ca.CommentCount,
    ca.Upvotes,
    ca.Downvotes,
    ca.PerformanceCategory,
    ca.ViewCategory,
    ca.PopularityRating,
    ca.ViewRank,
    ca.DaysSinceLastPost,
    ca.ImpactLevel,
    CASE 
        WHEN ca.UserCategory = 'Power User' AND ca.ViewCategory = 'High Views' THEN 'Elite Content Creator'
        WHEN ca.UserCategory = 'Active Contributor' AND ca.PerformanceCategory = 'Above Average' THEN 'Quality Contributor'
        WHEN ca.UserCategory = 'Badge Hunter' AND ca.ScoreCategory = 'High' THEN 'Achievement Focused'
        ELSE 'General Contributor'
    END as UserRole,
    CASE 
        WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM Posts) * 2 THEN 'Viral'
        WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM Posts) * 1.5 THEN 'Popular'
        WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'Standard'
        ELSE 'Underperforming'
    END as ViewPerformance,
    LEAD(ca.Reputation, 1) OVER (ORDER BY ca.Reputation DESC) as NextHigherReputation,
    LAG(ca.Reputation, 1) OVER (ORDER BY ca.Reputation ASC) as NextLowerReputation
FROM CombinedAnalysis ca
WHERE (ca.RepRank <= 20 OR ca.ViewRank <= 50)
AND (ca.PostId IS NOT NULL OR ca.UserId IS NOT NULL)
AND (ca.Title IS NOT NULL OR ca.DisplayName IS NOT NULL)
ORDER BY 
    CASE WHEN ca.RepRank <= 20 THEN ca.RepRank ELSE 1000 END,
    CASE WHEN ca.ViewRank <= 50 THEN ca.ViewRank ELSE 1000 END,
    ca.CreationDate DESC;