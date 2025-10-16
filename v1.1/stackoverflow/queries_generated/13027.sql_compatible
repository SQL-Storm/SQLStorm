WITH UserScores AS (
    SELECT 
        u.Id AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END), u.CreationDate) AS LastPostClosedDate
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        u.Id, u.CreationDate
),
PostMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY 
        p.OwnerUserId, p.Score
),
TopPerformers AS (
    SELECT 
        us.UserId,
        us.TotalUpvotes,
        us.TotalDownvotes,
        us.GoldBadges,
        pm.TotalPosts,
        pm.TotalScore,
        AVG(pm.TotalScore) OVER (PARTITION BY pm.OwnerUserId) AS AvgPostScore,
        us.LastPostClosedDate,
        pm.OwnerUserId
    FROM 
        UserScores us
    JOIN 
        PostMetrics pm ON us.UserId = pm.OwnerUserId
    WHERE 
        pm.PostRank <= 5
)
SELECT 
    tp.UserId,
    u.DisplayName,
    tp.TotalUpvotes,
    tp.TotalDownvotes,
    tp.GoldBadges,
    tp.TotalPosts,
    tp.TotalScore,
    tp.AvgPostScore,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - tp.LastPostClosedDate)) AS DaysSinceLastPostClosed,
    STRING_AGG(t.TagName, ', ') AS TopTags
FROM 
    TopPerformers tp
JOIN 
    Users u ON tp.UserId = u.Id
LEFT JOIN 
    Posts p ON tp.UserId = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
WHERE 
    tp.TotalScore > (SELECT AVG(TotalScore) FROM TopPerformers)
GROUP BY 
    tp.UserId, u.DisplayName, tp.TotalUpvotes, tp.TotalDownvotes, tp.GoldBadges, tp.TotalPosts, tp.TotalScore, tp.AvgPostScore, tp.LastPostClosedDate
ORDER BY 
    tp.TotalScore DESC
LIMIT 10;