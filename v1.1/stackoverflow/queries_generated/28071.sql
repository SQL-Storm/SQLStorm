-- {"query": "28071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1234} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2015-01-01'
    GROUP BY u.Id
), PostStats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 AS TagCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        COALESCE(ph.CloseCount, 0) AS CloseAttempts,
        RANK() OVER (ORDER BY p.Score * 0.5 + p.ViewCount * 0.3 DESC) AS EngagementRank
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(*) FILTER (WHERE PostHistoryTypeId = 10) AS CloseCount 
        FROM PostHistory 
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
)
SELECT 
    au.DisplayName,
    au.Reputation,
    ps.Title,
    ps.EngagementRank,
    (ps.Upvotes * 0.7 + ps.AnswerCount * 0.3) / NULLIF(ps.TagCount, 0) AS EngagementRatio,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS CommonTags,
    CASE 
        WHEN au.Reputation > 100000 THEN 'Legendary'
        WHEN au.GoldBadges >= 5 THEN 'Gold Specialist'
        WHEN ps.EngagementRank <= 50 THEN 'Top Contributor'
        ELSE 'Active User'
    END AS UserCategory
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ps.Id)
LEFT JOIN Posts p_tags ON au.Id = p_tags.OwnerUserId
LEFT JOIN Tags t ON p_tags.Tags LIKE CONCAT('%<', t.TagName, '>%')
WHERE au.ReputationRank <= 1000
  AND ps.TagCount BETWEEN 3 AND 5
  AND EXISTS (
    SELECT 1 FROM Votes v 
    WHERE v.PostId = ps.Id 
    AND v.VoteTypeId IN (2,8) 
    AND v.CreationDate > CURRENT_DATE - INTERVAL '1 year'
  )
GROUP BY au.Id, au.DisplayName, au.Reputation, ps.Title, ps.EngagementRank, ps.Upvotes, ps.AnswerCount, ps.TagCount
HAVING COUNT(DISTINCT t.Id) >= 2
ORDER BY 
    EngagementRatio DESC NULLS LAST, 
    au.ReputationRank
LIMIT 100;
