-- {"query": "2100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 364} 
WITH TopReputedUsers AS (
    SELECT 
        Id, DisplayName, Reputation, 
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
    WHERE Reputation > 1000
),
TagPostCounts AS (
    SELECT
        STRING_AGG(TagName, ', ') AS TagNames,
        COUNT(p.Id) AS PostCount
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.Id
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        (p.ViewCount + p.Score + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0)) AS EngagementScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
)
SELECT 
    u.DisplayName,
    u.Reputation,
    tm.TagNames,
    pm.EngagementScore,
    ph.Comment
FROM TopReputedUsers u
LEFT JOIN (
    SELECT UserId, Comment 
    FROM PostHistory 
    WHERE PostHistoryTypeId = 10
    AND CreationDate > (SELECT MIN(CreationDate) FROM Posts)
) ph ON ph.UserId = u.Id
JOIN PostMetrics pm ON pm.PostId IN (
    SELECT PostId 
    FROM Comments 
    WHERE UserId = u.Id
)
LEFT JOIN TagPostCounts tm ON tm.PostCount > 10
WHERE u.rank <= 10
ORDER BY u.Reputation DESC, pm.EngagementScore DESC;