-- {"query": "23083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 805} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RankInLocation,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.Class = 1  -- Gold badges only
    WHERE u.Reputation > 1000 AND (u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Name ELSE NULL END) >= 2
),
QuestionMetrics AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
           COALESCE(p.FavoriteCount, 0) AS Favorites,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS AvgBounty,
           STRING_AGG(t.TagName, ', ') AS TagList
    FROM Posts p
    INNER JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1  -- Questions
    AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount
),
CorrelatedSubqueryExample AS (
    SELECT q.PostId, q.OwnerUserId, q.Score, q.ViewCount,
           (SELECT COUNT(*) FROM PostHistory ph 
            WHERE ph.PostId = q.PostId 
            AND ph.PostHistoryTypeId IN (4,5,6)  -- Edits
            AND ph.CreationDate > q.CreationDate + INTERVAL '1 DAY'
            AND (ph.Text LIKE '%update%' OR ph.Comment IS NULL)) AS EditCountAfterDay
    FROM QuestionMetrics q
)
SELECT au.DisplayName || ' (' || COALESCE(au.Location, 'N/A') || ')' AS UserInfo,
       COUNT(DISTINCT cse.PostId) AS QuestionCount,
       AVG(cse.Score + COALESCE(cse.EditCountAfterDay, 0) * 0.5) AS WeightedAvgScore,
       SUM(NULLIF(cse.ViewCount, 0)) / NULLIF(COUNT(cse.PostId), 0) AS AvgViews,
       MAX(cse.Score) OVER (PARTITION BY au.Id) AS MaxScore,
       STRING_AGG(DISTINCT qm.TagList, '; ') AS AllTags
FROM ActiveUsers au
LEFT OUTER JOIN CorrelatedSubqueryExample cse ON au.Id = cse.OwnerUserId
INNER JOIN QuestionMetrics qm ON cse.PostId = qm.PostId
WHERE au.RankInLocation <= 5
  AND (cse.EditCountAfterDay > 2 OR qm.AvgBounty IS NOT NULL)
GROUP BY au.Id, au.DisplayName, au.Location
HAVING SUM(cse.Favorites) > 10

UNION ALL

SELECT 'Top Answerers' AS UserInfo,
       COUNT(DISTINCT p.Id) AS QuestionCount,
       AVG(p.Score) AS WeightedAvgScore,
       AVG(p.ViewCount) AS AvgViews,
       MAX(p.Score) OVER () AS MaxScore,
       NULL AS AllTags
FROM Posts p
WHERE p.PostTypeId = 2  -- Answers
AND p.ParentId IN (SELECT PostId FROM QuestionMetrics WHERE AvgBounty > 100)
GROUP BY p.OwnerUserId
HAVING COUNT(*) > 5
ORDER BY WeightedAvgScore DESC
LIMIT 10;
