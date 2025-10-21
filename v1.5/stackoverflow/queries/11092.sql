-- {"query": "11092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 705} 
WITH RecentPosts AS (
    SELECT 
        Posts.Id, Posts.Title, Posts.CreationDate, Posts.Score, Posts.ViewCount, Posts.AnswerCount, 
        Users.DisplayName AS OwnerDisplayName, Users.Reputation AS OwnerReputation,
        (SELECT COUNT(*) FROM Votes WHERE Votes.PostId = Posts.Id AND Votes.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(*) FROM Votes WHERE Votes.PostId = Posts.Id AND Votes.VoteTypeId = 3) AS DownvoteCount,
        (SELECT COUNT(*) FROM Comments WHERE Comments.PostId = Posts.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostHistory WHERE PostHistory.PostId = Posts.Id) AS EditCount,
        (SELECT COUNT(*) FROM PostLinks WHERE PostLinks.PostId = Posts.Id) AS LinkCount
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 month'
), 
BadgeCounts AS (
    SELECT 
        Badges.UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY Badges.UserId
)
SELECT 
    RecentPosts.Id, RecentPosts.Title, RecentPosts.CreationDate, RecentPosts.Score, RecentPosts.ViewCount, RecentPosts.AnswerCount,
    RecentPosts.OwnerDisplayName, RecentPosts.OwnerReputation,
    RecentPosts.UpvoteCount, RecentPosts.DownvoteCount, RecentPosts.CommentCount, RecentPosts.EditCount, RecentPosts.LinkCount,
    BadgeCounts.TotalBadges, BadgeCounts.GoldBadges, BadgeCounts.SilverBadges, BadgeCounts.BronzeBadges,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.AnswerCount, 0) AS BadgesPerAnswer,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.ViewCount, 0) AS BadgesPerView,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.Score, 0) AS BadgesPerScore,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.CommentCount, 0) AS BadgesPerComment,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.EditCount, 0) AS BadgesPerEdit,
    COALESCE(BadgeCounts.TotalBadges, 0) / NULLIF(RecentPosts.LinkCount, 0) AS BadgesPerLink
FROM RecentPosts
LEFT JOIN BadgeCounts ON RecentPosts.Id = BadgeCounts.UserId
ORDER BY RecentPosts.CreationDate DESC
LIMIT 100;