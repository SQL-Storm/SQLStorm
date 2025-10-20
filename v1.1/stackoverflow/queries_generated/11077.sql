-- {"query": "11077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 550} 

WITH RecentPosts AS (
    -- Select recent posts with their scores and view counts
    SELECT 
        Posts.Id, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.CreationDate, 
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation AS OwnerReputation
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
PostScores AS (
    -- Calculate average score and view count for each post type
    SELECT 
        PostTypeId, 
        AVG(Score) AS AvgScore, 
        AVG(ViewCount) AS AvgViewCount
    FROM RecentPosts
    GROUP BY PostTypeId
),
UserActivity AS (
    -- Select users with their recent activity and reputation
    SELECT 
        Users.Id, 
        Users.DisplayName, 
        Users.LastAccessDate, 
        Users.Reputation, 
        COUNT(Posts.Id) AS RecentPostsCount
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE Posts.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY Users.Id
),
BadgeEarnings AS (
    -- Select badges earned by users in the last 30 days
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgesEarned
    FROM Badges
    WHERE Badges.Date > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY Badges.UserId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.CreationDate, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    PostScores.PostTypeId, 
    PostScores.AvgScore, 
    PostScores.AvgViewCount, 
    UserActivity.DisplayName AS UserName, 
    UserActivity.LastAccessDate, 
    UserActivity.Reputation, 
    UserActivity.RecentPostsCount, 
    BadgeEarnings.BadgesEarned
FROM RecentPosts
JOIN PostScores ON RecentPosts.PostTypeId = PostScores.PostTypeId
JOIN UserActivity ON RecentPosts.OwnerUserId = UserActivity.Id
LEFT JOIN BadgeEarnings ON UserActivity.Id = BadgeEarnings.UserId
ORDER BY RecentPosts.CreationDate DESC, RecentPosts.Score DESC;
