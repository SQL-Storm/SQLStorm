-- {"query": "28083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1300} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    GROUP BY u.Id
),
PostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        ph.CreationDate AS LastEditDate,
        EXTRACT(DAY FROM (ph.CreationDate - p.CreationDate)) AS DaysToFirstEdit,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        STRING_AGG(DISTINCT t.TagName, '; ') FILTER (WHERE t.TagName IS NOT NULL) AS Tags,
        SUM(v.VoteTypeId) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId IN (4,5,6)
    LEFT JOIN Comments c 
        ON p.Id = c.PostId 
        AND c.CreationDate BETWEEN p.CreationDate AND p.CreationDate + INTERVAL '30 days'
    LEFT JOIN LATERAL (
        SELECT TRIM('><' FROM UNNEST(STRING_TO_ARRAY(p.Tags, '><'))) AS Tag
    ) pt ON true
    LEFT JOIN Tags t ON pt.Tag = t.TagName
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, ph.CreationDate, c.Id
)
SELECT 
    u.DisplayName,
    u.Reputation,
    us.BadgeCount,
    pa.Tags,
    pa.Upvotes,
    COALESCE(pa.DaysToFirstEdit, -1) AS DaysToEdit,
    (SELECT AVG(CommentCount) FROM PostAnalysis WHERE OwnerUserId = u.Id) AS AvgUserComments,
    CASE 
        WHEN us.ReputationRank <= 10 THEN 'Top 10'
        WHEN us.ReputationRank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END AS ReputationTier,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 2 
     AND EXISTS (SELECT 1 FROM Votes v2 WHERE v2.PostId = p2.Id AND v2.VoteTypeId = 1)) AS AcceptedAnswers
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
WHERE u.Reputation > 1000
  AND (u.Location LIKE '%USA%' OR u.Location IS NULL)
  AND EXISTS (
    SELECT 1 FROM Posts p3 
    WHERE p3.OwnerUserId = u.Id 
    AND p3.AnswerCount > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1)
  )
UNION ALL
SELECT 
    'Community Wiki' AS DisplayName,
    NULL AS Reputation,
    COUNT(*)::int AS BadgeCount,
    NULL AS Tags,
    SUM(v.VoteTypeId) AS Upvotes,
    NULL AS DaysToEdit,
    NULL AS AvgUserComments,
    'Wiki' AS ReputationTier,
    NULL AS AcceptedAnswers
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.CommunityOwnedDate IS NOT NULL
  AND p.OwnerUserId IS NULL
GROUP BY p.CommunityOwnedDate
HAVING COUNT(DISTINCT p.Id) > 5;