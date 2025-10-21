-- {"query": "11089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 510} 

WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.PostTypeId, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.AnswerCount, 
        Posts.CommentCount, 
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation AS OwnerReputation
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.CreationDate > NOW() - INTERVAL '1 month'
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalPosts, 
        SUM(Score) AS TotalScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(AnswerCount) AS TotalAnswers, 
        SUM(CommentCount) AS TotalComments
    FROM Posts
    GROUP BY UserId
),
BadgeSummary AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges, 
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    RecentPosts.Id, 
    RecentPosts.PostTypeId, 
    RecentPosts.Title, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    UserActivity.TotalPosts, 
    UserActivity.TotalScore, 
    UserActivity.TotalViews, 
    UserActivity.TotalAnswers, 
    UserActivity.TotalComments, 
    BadgeSummary.TotalBadges, 
    BadgeSummary.GoldBadges, 
    BadgeSummary.SilverBadges, 
    BadgeSummary.BronzeBadges
FROM RecentPosts
LEFT JOIN UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
ORDER BY RecentPosts.CreationDate DESC, RecentPosts.Score DESC
LIMIT 100;
