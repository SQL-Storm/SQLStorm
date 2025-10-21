WITH RecentPosts AS (
    SELECT 
        Posts.Id, 
        Posts.Title, 
        Posts.CreationDate, 
        Posts.Score, 
        Posts.ViewCount, 
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
        Posts.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
    GROUP BY 
        Posts.Id, Posts.Title, Posts.CreationDate, Posts.Score, Posts.ViewCount, Users.DisplayName, Users.Reputation
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
                SELECT SUM(Posts.Score) AS TotalScore 
                FROM Users 
                INNER JOIN Posts ON Users.Id = Posts.OwnerUserId 
                GROUP BY Users.Id
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
    RP.Id, 
    RP.Title, 
    RP.CreationDate, 
    RP.Score, 
    RP.ViewCount, 
    RP.OwnerDisplayName, 
    RP.OwnerReputation, 
    RP.CommentCount, 
    RP.UpvoteCount, 
    RP.DownvoteCount, 
    STRING_AGG(PT.TagName, ', ') AS Tags,
    PA.EditCount,
    PA.CloseCount,
    PA.ReopenCount,
    TU.DisplayName AS TopUserDisplayName, 
    TU.TotalScore
FROM 
    RecentPosts AS RP
LEFT JOIN 
    PostTags AS PT ON RP.Id = PT.Id
LEFT JOIN 
    PostActivity AS PA ON RP.Id = PA.Id
LEFT JOIN 
    TopUsers AS TU ON RP.OwnerDisplayName = TU.DisplayName
GROUP BY
    RP.Id, RP.Title, RP.CreationDate, RP.Score, RP.ViewCount, RP.OwnerDisplayName, RP.OwnerReputation, RP.CommentCount, RP.UpvoteCount, RP.DownvoteCount, PA.EditCount, PA.CloseCount, PA.ReopenCount, TU.DisplayName, TU.TotalScore
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC, 
    RP.CreationDate DESC
LIMIT 100;