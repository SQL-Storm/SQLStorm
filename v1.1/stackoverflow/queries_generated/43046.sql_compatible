WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        MAX(b.Date) AS LastBadgeEarned,
        COUNT(DISTINCT c.Id) AS CommentsCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    WHERE 
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    GROUP BY 
        u.Id,
        u.DisplayName,
        u.Reputation
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostsCount,
        TotalPostScore,
        BadgesCount,
        LastBadgeEarned,
        CommentsCount,
        RANK() OVER (ORDER BY (PostsCount + COALESCE(TotalPostScore,0) + COALESCE(BadgesCount,0) + COALESCE(CommentsCount,0)) DESC) AS Rank
    FROM 
        UserActivity
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.Reputation,
    tc.PostsCount,
    tc.TotalPostScore,
    tc.BadgesCount,
    tc.LastBadgeEarned,
    tc.CommentsCount,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS EditsCount,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 ELSE 0 END), 0) AS ModerationActionsCount
FROM 
    TopContributors tc
LEFT JOIN 
    PostHistory ph ON tc.UserId = ph.UserId
WHERE 
    tc.Rank <= 100
GROUP BY 
    tc.UserId, 
    tc.DisplayName, 
    tc.Reputation,
    tc.PostsCount,
    tc.TotalPostScore,
    tc.BadgesCount,
    tc.LastBadgeEarned,
    tc.CommentsCount
ORDER BY 
    (tc.PostsCount + COALESCE(tc.TotalPostScore,0) + COALESCE(tc.BadgesCount,0) + COALESCE(tc.CommentsCount,0)) DESC;