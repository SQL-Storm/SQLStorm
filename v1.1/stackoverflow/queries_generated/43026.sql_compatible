WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        AVG(ViewCount) AS AvgViewCount,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        b.TotalBadges,
        ua.TotalPosts,
        ua.TotalScore,
        ua.AvgViewCount,
        ua.LastActivityDate
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(Id) AS TotalBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01') - INTERVAL '1' YEAR
    ORDER BY u.Reputation DESC, b.TotalBadges DESC, ua.TotalScore DESC
    LIMIT 100
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(ph.Id) AS RevisionCount
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= DATE_TRUNC('year', DATE '2024-10-01') - INTERVAL '1' YEAR
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
    ORDER BY p.Score DESC, p.ViewCount DESC
    LIMIT 50
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.TotalBadges,
    tc.TotalPosts,
    tc.TotalScore,
    tc.AvgViewCount,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.ViewCount AS TopPostViewCount,
    tp.RevisionCount
FROM TopContributors tc
JOIN Posts p ON tc.Id = p.OwnerUserId
JOIN TopPosts tp ON p.Id = tp.Id
WHERE tc.LastActivityDate >= DATE_TRUNC('month', DATE '2024-10-01') - INTERVAL '1' MONTH
GROUP BY
    tc.DisplayName,
    tc.Reputation,
    tc.TotalBadges,
    tc.TotalPosts,
    tc.TotalScore,
    tc.AvgViewCount,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.RevisionCount
ORDER BY tc.Reputation DESC, tp.Score DESC;