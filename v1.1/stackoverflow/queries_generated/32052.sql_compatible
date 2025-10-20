WITH TopActiveUsers AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS TotalPosts
    FROM 
        Users
        JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY 
        Users.Id, Users.DisplayName
    HAVING 
        COUNT(Posts.Id) > 50
    ORDER BY 
        COUNT(Posts.Id) DESC
    LIMIT 10
),
UserBadges AS (
    SELECT 
        UserId, 
        COUNT(Id) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
),
PostDetails AS (
    SELECT 
        Posts.Id AS PostId, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.OwnerUserId AS OwnerUserId,
        Users.DisplayName AS PostOwnerDisplayName, 
        Posts.ViewCount, 
        Posts.Score
    FROM 
        Posts
        JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE 
        Posts.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
)
SELECT 
    TopActiveUsers.DisplayName, 
    TopActiveUsers.TotalPosts, 
    COALESCE(UserBadges.BadgeCount, 0) AS BadgeCount, 
    SUM(PostDetails.ViewCount) AS TotalViews, 
    AVG(PostDetails.Score) AS AvgScore
FROM 
    TopActiveUsers
    LEFT JOIN UserBadges ON TopActiveUsers.UserId = UserBadges.UserId
    LEFT JOIN PostDetails ON TopActiveUsers.UserId = PostDetails.OwnerUserId
GROUP BY 
    TopActiveUsers.DisplayName, 
    TopActiveUsers.TotalPosts, 
    UserBadges.BadgeCount
ORDER BY 
    TotalViews DESC, AvgScore DESC;