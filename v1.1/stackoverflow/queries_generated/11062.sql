-- {"query": "11062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 610} 

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
        COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 2 THEN Votes.UserId END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 3 THEN Votes.UserId END) AS DownVotes
    FROM Posts
    LEFT JOIN Votes ON Posts.Id = Votes.PostId
    LEFT JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY Posts.Id, Posts.PostTypeId, Posts.Title, Posts.CreationDate, Posts.Score, Posts.ViewCount, Posts.AnswerCount, Posts.CommentCount, Users.DisplayName
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(DISTINCT Posts.Id) AS TotalPosts, 
        SUM(Posts.Score) AS TotalScore, 
        SUM(Posts.ViewCount) AS TotalViews, 
        SUM(Posts.AnswerCount) AS TotalAnswers, 
        SUM(Posts.CommentCount) AS TotalComments
    FROM Posts
    GROUP BY UserId
),
BadgeSummary AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalBadges, 
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
    RecentPosts.UpVotes,
    RecentPosts.DownVotes,
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
