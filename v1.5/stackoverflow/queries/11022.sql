-- {"query": "11022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 582} 
WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Users.DisplayName AS OwnerDisplayName, 
        COUNT(DISTINCT Comments.Id) AS CommentCount
    FROM 
        Posts
    LEFT JOIN 
        Comments ON Posts.Id = Comments.PostId
    LEFT JOIN 
        Users ON Posts.OwnerUserId = Users.Id
    WHERE 
        Posts.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 days' 
        AND Posts.PostTypeId = 1
    GROUP BY 
        Posts.Id, Posts.Title, Posts.CreationDate, Posts.Score, Posts.ViewCount, Users.DisplayName
),
TopScoredPosts AS (
    SELECT 
        Id, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerDisplayName, 
        CommentCount,
        ROW_NUMBER() OVER (PARTITION BY OwnerDisplayName ORDER BY Score DESC) AS Rank
    FROM 
        RecentPosts
    WHERE 
        Score > 10
),
BadgesByClass AS (
    SELECT 
        UserId, 
        Class, 
        COUNT(*) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId, Class
),
BadgeSummary AS (
    SELECT 
        UserId, 
        SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN BadgeCount ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN BadgeCount ELSE 0 END) AS BronzeBadges
    FROM 
        BadgesByClass
    GROUP BY 
        UserId
)
SELECT 
    T1.Id, 
    T1.Title, 
    T1.CreationDate, 
    T1.Score, 
    T1.ViewCount, 
    T1.OwnerDisplayName, 
    T1.CommentCount, 
    T1.Rank, 
    T2.GoldBadges, 
    T2.SilverBadges, 
    T2.BronzeBadges
FROM 
    TopScoredPosts T1
LEFT JOIN 
    BadgeSummary T2 ON T1.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = T2.UserId)
WHERE 
    T2.GoldBadges > 5 
    OR T2.SilverBadges > 10 
    OR T2.BronzeBadges > 20
ORDER BY 
    T1.Score DESC, 
    T1.ViewCount DESC, 
    T1.CreationDate DESC;