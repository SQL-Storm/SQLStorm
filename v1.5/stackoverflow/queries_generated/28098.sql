-- {"query": "28098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1412} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    GROUP BY u.Id, b.Class, u.Reputation
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT MAX(ph.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName), 'Untagged') AS Tags,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPosts,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatePosts
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Tags t ON t.Id = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<>', ''), ','))
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id
)
SELECT 
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS Location,
    pm.Tags,
    pm.Score * 2 + pm.ViewCount * 0.1 + pm.AnswerCount * 5 AS PostQualityScore,
    us.GoldBadges,
    us.ReputationRank,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.PostId = pm.PostId AND v.VoteTypeId = 2) AS Upvotes,
    ph.Text AS LastEditSummary,
    CASE 
        WHEN us.PostCount > 100 THEN 'Prolific'
        WHEN us.PostCount BETWEEN 50 AND 100 THEN 'Active'
        ELSE 'Casual'
    END AS UserActivityLevel,
    pm.LinkedPosts + pm.DuplicatePosts * 3 AS PostNetworkImpact,
    (SELECT AVG(Score) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id) AS AvgPostScore
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
JOIN PostMetrics pm ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pm.PostId)
LEFT JOIN PostHistory ph ON pm.PostId = ph.PostId AND ph.CreationDate = pm.LastEditDate
WHERE us.GoldBadges > 0
  AND EXISTS (
      SELECT 1 
      FROM Badges b 
      WHERE b.UserId = u.Id AND b.Name LIKE '%Legendary%'
  )
  AND u.Reputation > (SELECT AVG(Reputation) FROM Users)
ORDER BY PostQualityScore DESC, us.ReputationRank
LIMIT 100;
