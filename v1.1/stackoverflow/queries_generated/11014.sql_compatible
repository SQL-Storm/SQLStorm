WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
        Posts.OwnerUserId,
        Users.DisplayName AS OwnerDisplayName, 
        Users.Reputation AS OwnerReputation,
        COUNT(DISTINCT Comments.Id) AS CommentCount,
        SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Posts
    LEFT JOIN 
        Users ON Posts.OwnerUserId = Users.Id
    LEFT JOIN 
        Comments ON Posts.Id = Comments.PostId
    LEFT JOIN 
        Votes ON Posts.Id = Votes.PostId
    WHERE 
        Posts.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY 
        Posts.Id, Posts.Title, Posts.CreationDate, Posts.Score, Posts.ViewCount, Posts.OwnerUserId, Users.DisplayName, Users.Reputation
),
TopUsers AS (
    SELECT 
        Users.Id, 
        Users.DisplayName, 
        SUM(Posts.Score) AS TotalScore
    FROM 
        Users
    INNER JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    GROUP BY 
        Users.Id, Users.DisplayName
    HAVING 
        SUM(Posts.Score) > (
            SELECT AVG(TotalScore) FROM (
                SELECT SUM(p2.Score) AS TotalScore 
                FROM Users u2 
                INNER JOIN Posts p2 ON u2.Id = p2.OwnerUserId 
                GROUP BY u2.Id
            ) AS AvgScores
        )
),
PostTags AS (
    SELECT 
        Posts.Id, 
        Tags.TagName
    FROM 
        Posts
    INNER JOIN 
        Tags ON Posts.Id = Tags.ExcerptPostId OR Posts.Id = Tags.WikiPostId
),
PostActivity AS (
    SELECT 
        Posts.Id, 
        Posts.Title, 
        COUNT(DISTINCT PostHistory.Id) AS EditCount,
        COUNT(DISTINCT CASE WHEN PostHistory.PostHistoryTypeId = 10 THEN PostHistory.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN PostHistory.PostHistoryTypeId = 11 THEN PostHistory.Id END) AS ReopenCount
    FROM 
        Posts
    LEFT JOIN 
        PostHistory ON Posts.Id = PostHistory.PostId
    GROUP BY 
        Posts.Id, Posts.Title
)
SELECT 
    RecentPosts.Id, 
    RecentPosts.Title, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.OwnerReputation, 
    RecentPosts.CommentCount, 
    RecentPosts.UpvoteCount, 
    RecentPosts.DownvoteCount, 
    STRING_AGG(PostTags.TagName, ', ') AS Tags,
    PostActivity.EditCount,
    PostActivity.CloseCount,
    PostActivity.ReopenCount,
    TopUsers.DisplayName AS TopUserDisplayName, 
    TopUsers.TotalScore
FROM 
    RecentPosts
LEFT JOIN 
    PostTags ON RecentPosts.Id = PostTags.Id
LEFT JOIN 
    PostActivity ON RecentPosts.Id = PostActivity.Id
LEFT JOIN 
    TopUsers ON RecentPosts.OwnerUserId = TopUsers.Id
GROUP BY
    RecentPosts.Id, RecentPosts.Title, RecentPosts.CreationDate, RecentPosts.Score, RecentPosts.ViewCount, RecentPosts.OwnerUserId, RecentPosts.OwnerDisplayName, RecentPosts.OwnerReputation, RecentPosts.CommentCount, RecentPosts.UpvoteCount, RecentPosts.DownvoteCount, PostActivity.EditCount, PostActivity.CloseCount, PostActivity.ReopenCount, TopUsers.DisplayName, TopUsers.TotalScore
ORDER BY 
    RecentPosts.Score DESC, 
    RecentPosts.ViewCount DESC, 
    RecentPosts.CreationDate DESC
LIMIT 100;