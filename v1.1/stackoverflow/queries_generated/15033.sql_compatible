WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS UserAvgPostScore,
        -- count questions per user: use FILTER (WHERE ...) or SUM(CASE WHEN ...) as window expression
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS UserQuestionCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
), UserPostMetrics AS (
    SELECT 
        UserId,
        DisplayName,
        MAX(CASE WHEN PostRank = 1 THEN PostId END) AS TopPostId,
        MAX(UserAvgPostScore) AS AvgPostScore,
        MAX(UserQuestionCount) AS TotalQuestions,
        SUM(CASE WHEN CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year' THEN 1 ELSE 0 END) AS RecentPostCount
    FROM RankedUserPosts
    GROUP BY UserId, DisplayName
)
SELECT 
    upm.UserId,
    upm.DisplayName,
    upm.AvgPostScore,
    upm.TotalQuestions,
    upm.RecentPostCount,
    p.Title AS TopPostTitle,
    p.Score AS TopPostScore,
    COALESCE(v.UpVotes, 0) AS UserUpVotes,
    COALESCE(v.DownVotes, 0) AS UserDownVotes,
    ROUND(100.0 * COALESCE(v.UpVotes, 0) / NULLIF(COALESCE(v.UpVotes, 0) + COALESCE(v.DownVotes, 0), 0), 2) AS VotePercentage,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upm.UserId) AS TotalBadges
FROM UserPostMetrics upm
JOIN Posts p ON upm.TopPostId = p.Id
LEFT JOIN Users v ON upm.UserId = v.Id
WHERE 
    upm.AvgPostScore > 10 
    AND upm.TotalQuestions > 5
    AND upm.RecentPostCount > 0
GROUP BY
    upm.UserId,
    upm.DisplayName,
    upm.AvgPostScore,
    upm.TotalQuestions,
    upm.RecentPostCount,
    p.Title,
    p.Score,
    v.UpVotes,
    v.DownVotes,
    upm.TopPostId
ORDER BY 
    upm.AvgPostScore * upm.TotalQuestions DESC
LIMIT 100;