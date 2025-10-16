WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT ph.Id) AS EditCount,
        -- convert windowed moving average to an aggregated approximation: average of last 4 posts' scores per user
        AVG(sub.Score) AS AvgScoreLast4Posts,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN (
        -- get up to 4 most recent posts per user by CreationDate and average their scores
        SELECT p2.OwnerUserId, p2.Score
        FROM (
            SELECT 
                p2.*,
                ROW_NUMBER() OVER (PARTITION BY p2.OwnerUserId ORDER BY p2.CreationDate DESC, p2.Id DESC) AS rn
            FROM Posts p2
        ) p2
        WHERE p2.rn <= 4
    ) sub ON sub.OwnerUserId = u.Id
    WHERE u.Reputation > 1000 
      AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
PostDetails AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ph.Comment AS CloseReasonComment,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC, p.Id DESC) AS PostRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.PostsCount,
    ua.TotalScore,
    ua.EditCount,
    ua.AvgScoreLast4Posts,
    ua.LastBadgeDate,
    pd.Id AS LastClosedQuestionId,
    pd.Score AS LastClosedQuestionScore,
    pd.CloseReasonComment,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month') AS RecentCommentCount,
    CASE 
        WHEN ua.PostsCount > 100 THEN 'Power User'
        WHEN ua.PostsCount BETWEEN 50 AND 100 THEN 'Active User'
        ELSE 'Casual User'
    END AS UserCategory
FROM UserActivity ua
LEFT JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId AND pd.PostRank = 1
WHERE ua.EditCount > 10 AND ua.AvgScoreLast4Posts > 5
ORDER BY ua.TotalScore DESC
LIMIT 10;