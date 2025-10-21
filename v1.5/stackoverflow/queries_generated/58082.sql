-- {"query": "58082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2088} 

WITH MonthlyUserActivity AS (
    SELECT
        u.Id AS UserId,
        DATE_TRUNC('month', p.CreationDate) AS ActivityMonth,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.Date >= DATE_TRUNC('year', CURRENT_DATE)) AS GoldBadgesEarned,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY COUNT(p.Id) + COUNT(c.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= DATE_TRUNC('year', CURRENT_DATE)
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= DATE_TRUNC('year', CURRENT_DATE)
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 8)
    WHERE u.Reputation > 10000
      AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 2)
    GROUP BY u.Id, ActivityMonth
)
SELECT 
    m.UserId,
    u.DisplayName,
    m.ActivityMonth,
    m.PostCount,
    m.CommentCount,
    m.Upvotes,
    m.AvgQuestionScore,
    m.GoldBadgesEarned,
    m.ActivityRank,
    (SELECT STRING_AGG(TagName, ', ' ORDER BY COUNT(pt.Id) DESC LIMIT 3)
     FROM Posts p2
     JOIN Tags t ON ARRAY_TO_STRING(STRING_TO_ARRAY(REPLACE(p2.Tags, '><', ','), ','), ',') LIKE '%' || t.TagName || '%'
     WHERE p2.OwnerUserId = m.UserId AND p2.CreationDate >= DATE_TRUNC('year', CURRENT_DATE)
     GROUP BY t.TagName) AS TopTags
FROM MonthlyUserActivity m
JOIN Users u ON m.UserId = u.Id
WHERE m.PostCount > 5 OR m.CommentCount > 20
ORDER BY m.ActivityMonth DESC, m.ActivityRank, u.DisplayName
LIMIT 1000;
