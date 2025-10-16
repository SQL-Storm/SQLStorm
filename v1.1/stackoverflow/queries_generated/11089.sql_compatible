WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
),
UserActivity AS (
    SELECT 
        p.OwnerUserId AS UserId, 
        COUNT(*) AS TotalPosts, 
        SUM(p.Score) AS TotalScore, 
        SUM(p.ViewCount) AS TotalViews, 
        SUM(p.AnswerCount) AS TotalAnswers, 
        SUM(p.CommentCount) AS TotalComments
    FROM Posts p
    GROUP BY p.OwnerUserId
),
BadgeSummary AS (
    SELECT 
        b.UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    rp.Id, 
    rp.PostTypeId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.TotalViews, 
    ua.TotalAnswers, 
    ua.TotalComments, 
    bs.TotalBadges, 
    bs.GoldBadges, 
    bs.SilverBadges, 
    bs.BronzeBadges
FROM RecentPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN BadgeSummary bs ON rp.OwnerUserId = bs.UserId
ORDER BY rp.CreationDate DESC, rp.Score DESC
LIMIT 100;