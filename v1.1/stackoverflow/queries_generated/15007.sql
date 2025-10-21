-- {"query": "15007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 600}
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.PostTypeId,
        p.Tags,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostRank,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC) AS YearlyViewRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalytics AS (
    SELECT 
        UserId,
        DisplayName,
        MAX(PostRank) AS MaxPostRank,
        AVG(COALESCE(Score, 0)) AS AvgPostScore,
        COUNT(DISTINCT UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS UniqueTagCount
    FROM RankedUserPosts
    GROUP BY UserId, DisplayName
    HAVING MAX(PostRank) <= 10
)
SELECT 
    ta.UserId,
    ta.DisplayName,
    ta.MaxPostRank,
    ta.AvgPostScore,
    ta.UniqueTagCount,
    v.Count AS TotalVotes,
    CASE 
        WHEN ta.AvgPostScore > 10 THEN 'High Performer'
        WHEN ta.AvgPostScore BETWEEN 5 AND 10 THEN 'Moderate Contributor'
        ELSE 'Emerging User'
    END AS UserCategory,
    COALESCE(b.GoldBadges, 0) AS GoldBadgeCount
FROM TagAnalytics ta
LEFT JOIN (
    SELECT UserId, COUNT(*) AS Count 
    FROM Votes 
    WHERE VoteTypeId IN (2, 3) 
    GROUP BY UserId
) v ON ta.UserId = v.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges 
    FROM Badges 
    WHERE Class = 1 
    GROUP BY UserId
) b ON ta.UserId = b.UserId
WHERE ta.UniqueTagCount > 5
ORDER BY ta.AvgPostScore DESC, v.Count DESC
LIMIT 100;
