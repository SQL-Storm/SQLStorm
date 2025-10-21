-- {"query": "22083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 767} 
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.Id) AS PostRankWithinUser,
    CASE 
      WHEN p.Tags IS NOT NULL THEN SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><', 1)
      ELSE NULL 
    END AS FirstTag,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) - 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS NetUpvotes,
    COUNT(*) OVER (PARTITION BY p.Id) AS TotalVotesOnPost,
    AVG(c.Score) OVER (PARTITION BY p.Id) AS AvgCommentScore
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
  LEFT JOIN Comments c ON p.Id = c.PostId
  WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.CreationDate > '2020-01-01'
),
UserAggregates AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    SUM(rp.Score) AS TotalPostScore,
    AVG(rp.NetUpvotes) AS AvgNetUpvotesPerPost,
    RANK() OVER (ORDER BY SUM(rp.Score) DESC, COUNT(b.Id) DESC) AS UserRank
  FROM Users u
  LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate > '2020-01-01'
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
FilteredResults AS (
  SELECT rp.Id, rp.Title, rp.FirstTag, rp.NetUpvotes, rp.TotalVotesOnPost, rp.AvgCommentScore,
         ua.DisplayName, ua.Reputation, ua.BadgeCount, ua.UserRank, ua.TotalPostScore, ua.AvgNetUpvotesPerPost,
         CASE WHEN rp.NetUpvotes > (SELECT AVG(NetUpvotes) FROM RankedPosts) THEN 'Above Avg' ELSE 'Below Avg' END AS PopularityLevel
  FROM RankedPosts rp
  FULL OUTER JOIN UserAggregates ua ON rp.OwnerUserId = ua.UserId
  WHERE rp.NetUpvotes > 50 OR ua.UserRank <= 100
)
SELECT * 
FROM FilteredResults 
WHERE FirstTag IS NOT NULL AND PopularityLevel = 'Above Avg' 
  AND Id IN (
    SELECT DISTINCT p.Id 
    FROM Posts p 
    WHERE p.Id = FilteredResults.Id 
      AND EXISTS (
        SELECT 1 
        FROM PostLinks pl 
        WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
      )
  )
UNION ALL
SELECT * 
FROM FilteredResults 
WHERE FirstTag IS NULL AND PopularityLevel = 'Below Avg' 
  AND Id IN (
    SELECT DISTINCT p.Id 
    FROM Posts p 
    WHERE p.Id = FilteredResults.Id 
      AND NOT EXISTS (
        SELECT 1 
        FROM Comments c 
        WHERE c.PostId = p.Id AND c.Score < 0
      )
  )
ORDER BY UserRank, NetUpvotes DESC, Id
LIMIT 500;