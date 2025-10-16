-- {"query": "23095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 724} 

WITH TopTags AS (
    SELECT t.TagName, t.Count AS TagCount,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserBadgeStats AS (
    SELECT u.Id AS UserId, u.Reputation,
           COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           COALESCE(AVG(NULLIF(b.Date, NULL)), u.CreationDate) AS AvgBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(b.Id) > 5 OR u.Reputation > 10000
),
PostMetrics AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           STRING_AGG(SUBSTRING(pt.Name, 1, 10), ', ') AS PostTypeSummary
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate > '2010-01-01' AND (p.Tags LIKE '%sql%' OR p.Tags IS NULL)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount
),
ElaborateQuery AS (
    SELECT ubs.UserId, ubs.Reputation, ubs.BadgeCount, ubs.GoldBadges,
           pm.PostId, pm.Score, pm.ViewCount,
           RANK() OVER (PARTITION BY ubs.UserId ORDER BY pm.Score DESC) AS PostRank,
           COALESCE(pm.PositiveComments, 0) + ubs.GoldBadges AS CombinedMetric,
           CASE WHEN pm.AnswerCount IS NULL THEN 'No Answers'
                WHEN pm.AnswerCount > 5 THEN CONCAT('High Answers: ', pm.AnswerCount)
                ELSE 'Low Answers' END AS AnswerCategory,
           (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = pm.PostId AND v.VoteTypeId = 2) AS LastUpvote
    FROM UserBadgeStats ubs
    LEFT OUTER JOIN PostMetrics pm ON ubs.UserId = pm.OwnerUserId
    WHERE ubs.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0) * 1.5
      AND EXISTS (SELECT 1 FROM TopTags tt WHERE tt.TagName IN (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) FROM Posts p WHERE p.Id = pm.PostId))
)
SELECT * FROM ElaborateQuery
UNION ALL
SELECT ubs.UserId, ubs.Reputation, ubs.BadgeCount, ubs.GoldBadges,
       NULL AS PostId, 0 AS Score, 0 AS ViewCount,
       NULL AS PostRank, ubs.GoldBadges AS CombinedMetric,
       'No Posts' AS AnswerCategory, NULL AS LastUpvote
FROM UserBadgeStats ubs
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ubs.UserId)
ORDER BY Reputation DESC, BadgeCount DESC
LIMIT 1000;
