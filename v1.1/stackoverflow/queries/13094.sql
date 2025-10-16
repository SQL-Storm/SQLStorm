-- {"query": "13094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 467} 
WITH UserReputationCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 10 ELSE 0 END) -
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 2 ELSE 0 END) AS TotalReputation
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
HighQualityPosts AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS HighQualityPostsCount
    FROM Posts p
    WHERE p.Score > 25 AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
EditedQuestions AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedQuestionsCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND EXISTS (
        SELECT 1 FROM Posts p WHERE p.Id = ph.PostId AND p.PostTypeId = 1
    )
    GROUP BY ph.UserId
)
SELECT 
    ur.UserId,
    ur.DisplayName,
    ur.TotalReputation,
    COALESCE(hqp.HighQualityPostsCount, 0) AS HighQualityPostsCount,
    COALESCE(eq.EditedQuestionsCount, 0) AS EditedQuestionsCount,
    ROW_NUMBER() OVER (ORDER BY ur.TotalReputation DESC) AS ReputationRank
FROM UserReputationCTE ur
LEFT JOIN HighQualityPosts hqp ON ur.UserId = hqp.OwnerUserId
LEFT JOIN EditedQuestions eq ON ur.UserId = eq.UserId
WHERE ur.TotalReputation > (SELECT AVG(TotalReputation) * 2 FROM UserReputationCTE)
  AND LENGTH(ur.DisplayName) > 5
  AND ur.DisplayName NOT LIKE '%test%'
ORDER BY ReputationRank, EditedQuestionsCount DESC
LIMIT 100;