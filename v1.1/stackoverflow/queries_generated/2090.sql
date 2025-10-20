-- {"query": "2090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 416} 

WITH RecentUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        STRING_AGG(t.TagName, ', ') AS Tags
    FROM Posts p
    LEFT JOIN Tags t ON '<' || p.Tags || '>' LIKE '%><' || t.TagName || '><%'
    WHERE p.PostTypeId = 1 AND p.Score > 0
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score
),
UserActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    COALESCE(ru.BadgeCount, 0) AS BadgeCount,
    ua.PostCount,
    ua.CommentCount,
    tq.Title AS TopQuestionTitle,
    tq.Tags AS TopQuestionTags,
    tq.ViewCount AS TopQuestionViewCount,
    tq.Score AS TopQuestionScore
FROM RecentUsers ru
LEFT JOIN UserActivity ua ON ru.UserId = ua.UserId
LEFT JOIN TopQuestions tq ON ru.UserId = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = tq.PostId LIMIT 1)
ORDER BY ru.Reputation DESC, ru.BadgeCount DESC, ua.PostCount DESC;
