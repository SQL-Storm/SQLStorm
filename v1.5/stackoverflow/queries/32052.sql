WITH TopActiveUsers AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS TotalPosts
    FROM 
        Users
        JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > (DATE '2024-10-01' - INTERVAL '1 year')
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
        Users.DisplayName, 
        Posts.ViewCount, 
        Posts.Score, 
        Posts.OwnerUserId
    FROM 
        Posts
        JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE 
        Posts.CreationDate > (DATE '2024-10-01' - INTERVAL '1 year')
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
    COALESCE(UserBadges.BadgeCount, 0)
ORDER BY 
    TotalViews DESC, AvgScore DESC;