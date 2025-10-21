-- {"query": "11033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 529} 

WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.Title, 
        Posts.PostTypeId, 
        Posts.CreationDate, 
        Posts.Score, 
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation,
        (SELECT COUNT(*) FROM Votes WHERE Posts.Id = Votes.PostId) AS VoteCount,
        (SELECT COUNT(*) FROM Comments WHERE Posts.Id = Comments.PostId) AS CommentCount
    FROM 
        Posts
    JOIN 
        Users ON Posts.OwnerUserId = Users.Id
    WHERE 
        Posts.CreationDate > NOW() - INTERVAL '1 month'
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalActivity
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        UserId
),
BadgeSummary AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalBadges, 
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    RecentPosts.Id, 
    RecentPosts.Title, 
    RecentPosts.PostTypeId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.Reputation, 
    RecentPosts.VoteCount, 
    RecentPosts.CommentCount, 
    UserActivity.TotalActivity, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges
FROM 
    RecentPosts
JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
WHERE 
    RecentPosts.Score > 0 
    AND RecentPosts.PostTypeId = 1
    AND UserActivity.TotalActivity > 10
    AND BadgeSummary.TotalBadges > 5
ORDER BY 
    RecentPosts.Score DESC, 
    RecentPosts.CreationDate DESC
LIMIT 10;
