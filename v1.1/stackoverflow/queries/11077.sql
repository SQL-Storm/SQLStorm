WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.CreationDate, 
        Posts.OwnerUserId,
        Posts.PostTypeId,
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation AS OwnerReputation
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
PostScores AS (
    SELECT 
        PostTypeId, 
        AVG(Score) AS AvgScore, 
        AVG(ViewCount) AS AvgViewCount
    FROM RecentPosts
    GROUP BY PostTypeId
),
UserActivity AS (
    SELECT 
        Users.Id, 
        Users.DisplayName, 
        Users.LastAccessDate, 
        Users.Reputation, 
        COUNT(Posts.Id) AS RecentPostsCount
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId AND Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    GROUP BY Users.Id, Users.DisplayName, Users.LastAccessDate, Users.Reputation
),
BadgeEarnings AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgesEarned
    FROM Badges
    WHERE Badges.Date > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
    GROUP BY Badges.UserId
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.CreationDate, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    RecentPosts.PostTypeId, 
    PostScores.AvgScore, 
    PostScores.AvgViewCount, 
    UserActivity.DisplayName AS UserName, 
    UserActivity.LastAccessDate, 
    UserActivity.Reputation, 
    UserActivity.RecentPostsCount, 
    COALESCE(BadgeEarnings.BadgesEarned, 0) AS BadgesEarned
FROM RecentPosts
JOIN PostScores ON RecentPosts.PostTypeId = PostScores.PostTypeId
JOIN UserActivity ON RecentPosts.OwnerUserId = UserActivity.Id
LEFT JOIN BadgeEarnings ON UserActivity.Id = BadgeEarnings.UserId
ORDER BY RecentPosts.CreationDate DESC, RecentPosts.Score DESC;