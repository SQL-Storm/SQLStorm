WITH MonthlyUserActivity AS (
    SELECT
        u.Id AS UserId,
        DATE_TRUNC('month', p.CreationDate) AS ActivityMonth,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.Date >= DATE_TRUNC('year', DATE '2024-10-01')) AS GoldBadgesEarned,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY COUNT(p.Id) + COUNT(c.Id) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01')
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01')
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 8)
    WHERE u.Reputation > 10000
      AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 2)
    GROUP BY u.Id, DATE_TRUNC('month', p.CreationDate)
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
    (SELECT STRING_AGG(top3.TagName, ', ')
     FROM (
       SELECT t.TagName
       FROM Posts p2
       CROSS JOIN LATERAL (
         SELECT TRIM(tag) AS TagName
         FROM (
           SELECT UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p2.Tags, '<', ''), '>', ','), ',')) AS tag
         ) s
       ) t
       WHERE t.TagName <> ''
         AND p2.OwnerUserId = m.UserId
         AND p2.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01')
       GROUP BY t.TagName
       ORDER BY COUNT(p2.Id) DESC
       LIMIT 3
     ) AS top3
    ) AS TopTags
FROM MonthlyUserActivity m
JOIN Users u ON m.UserId = u.Id
WHERE m.PostCount > 5 OR m.CommentCount > 20
GROUP BY m.UserId, u.DisplayName, m.ActivityMonth, m.PostCount, m.CommentCount, m.Upvotes, m.AvgQuestionScore, m.GoldBadgesEarned, m.ActivityRank
ORDER BY m.ActivityMonth DESC, m.ActivityRank, u.DisplayName
LIMIT 1000;