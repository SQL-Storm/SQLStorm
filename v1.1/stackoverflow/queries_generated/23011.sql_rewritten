-- {"query": "23011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 755} 
WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RankInLocation,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS WeightedBadgeScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT b.Id) > 0 OR u.Reputation > 1000
),
QuestionStats AS (
    SELECT p.Id AS QuestionId, p.Title, p.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           STRING_AGG(SUBSTRING(t.TagName, 1, 10) || ' (' || t.Count || ')', ', ') AS TagSummary
    FROM Posts p
    INNER JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.ViewCount IS NOT NULL
    GROUP BY p.Id, p.Title, p.ViewCount
    HAVING SUM(t.Count) > 1000
),
AnswerStats AS (
    SELECT p.ParentId AS QuestionId, COUNT(p.Id) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore,
           MAX(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAccepted
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
)
SELECT tu.DisplayName, tu.RankInLocation, tu.WeightedBadgeScore,
       qs.Title, qs.ViewCount, qs.PositiveComments, qs.TagSummary,
       COALESCE(as2.AnswerCount, 0) AS AnswerCount,
       COALESCE(as2.AvgAnswerScore, 0) AS AvgAnswerScore,
       CASE WHEN as2.HasAccepted = 1 THEN 'Yes' ELSE 'No' END AS AcceptedStatus,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = qs.QuestionId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.UserId = tu.Id) AS UserEditsOnQuestion
FROM TopUsers tu
LEFT OUTER JOIN Posts p ON tu.Id = p.OwnerUserId AND p.PostTypeId = 1
INNER JOIN QuestionStats qs ON qs.QuestionId = p.Id
LEFT JOIN AnswerStats as2 ON as2.QuestionId = qs.QuestionId
WHERE tu.RankInLocation <= 5
   AND (qs.ViewCount > 10000 OR qs.PositiveComments > 5)
   AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = qs.QuestionId AND v.VoteTypeId = 2)
UNION ALL
SELECT tu.DisplayName || ' (No Questions)', tu.RankInLocation, tu.WeightedBadgeScore,
       NULL AS Title, NULL AS ViewCount, NULL AS PositiveComments, NULL AS TagSummary,
       NULL AS AnswerCount, NULL AS AvgAnswerScore, NULL AS AcceptedStatus, 0 AS UserEditsOnQuestion
FROM TopUsers tu
WHERE NOT EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = tu.Id AND p2.PostTypeId = 1)
ORDER BY WeightedBadgeScore DESC, RankInLocation ASC;