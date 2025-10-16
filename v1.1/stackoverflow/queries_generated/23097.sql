-- {"query": "23097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 940} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName, 
           COALESCE(u.Location, 'Unknown') AS Location,
           ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRank
    FROM Users u
    WHERE u.Reputation > 1000
      AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate > '2020-01-01')
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount, 
           STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS GoldBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(*) > 5
),
QuestionStats AS (
    SELECT p.Id AS QuestionId, p.OwnerUserId, p.Score, p.ViewCount,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AvgBounty
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%sql%'
),
AnswerStats AS (
    SELECT p.ParentId AS QuestionId, AVG(p.Score) AS AvgAnswerScore,
           COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT OUTER JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
    HAVING AVG(p.Score) > 0
),
CombinedStats AS (
    SELECT qs.QuestionId, qs.OwnerUserId, qs.Score, qs.ViewCount, qs.AvgBounty,
           COALESCE(as_.AvgAnswerScore, 0) AS AvgAnswerScore,
           COALESCE(as_.CommentCount, 0) AS CommentCount
    FROM QuestionStats qs
    FULL OUTER JOIN AnswerStats as_ ON as_.QuestionId = qs.QuestionId
    WHERE qs.Score + COALESCE(as_.AvgAnswerScore, 0) > 10
),
TagUsage AS (
    SELECT t.TagName, COUNT(p.Id) AS QuestionCount
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    INTERSECT
    SELECT t.TagName, COUNT(p.Id) AS QuestionCount
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
)
SELECT au.DisplayName || ' (' || au.Location || ')' AS UserInfo,
       au.Reputation,
       COALESCE(ub.BadgeCount, 0) AS BadgeCount,
       ub.GoldBadges,
       SUM(cs.Score) AS TotalScore,
       AVG(cs.ViewCount) AS AvgViews,
       MAX(cs.AvgBounty) AS MaxBounty,
       AVG(cs.AvgAnswerScore) AS OverallAvgAnswerScore,
       COUNT(DISTINCT cs.QuestionId) AS QuestionCount,
       STRING_AGG(tu.TagName, '; ') AS UsedTags,
       RANK() OVER (ORDER BY SUM(cs.Score) DESC) AS OverallRank
FROM ActiveUsers au
LEFT OUTER JOIN UserBadges ub ON ub.UserId = au.Id
INNER JOIN CombinedStats cs ON cs.OwnerUserId = au.Id
LEFT OUTER JOIN (
    SELECT ph.PostId, COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
) edits ON edits.PostId = cs.QuestionId
INNER JOIN TagUsage tu ON 1=1  -- Cross join for demonstration, but filtered in predicate
WHERE au.LocationRank <= 5
  AND (cs.AvgBounty IS NULL OR cs.AvgBounty > 50)
  AND edits.EditCount > 2
  AND tu.QuestionCount > (SELECT AVG(QuestionCount) FROM TagUsage)
GROUP BY au.Id, au.DisplayName, au.Location, au.Reputation, ub.BadgeCount, ub.GoldBadges
HAVING SUM(cs.Score) > 100
ORDER BY OverallRank;
