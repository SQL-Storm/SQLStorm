
WITH UserStatistics AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
        SUM(CASE WHEN P.Score < 0 THEN 1 ELSE 0 END) AS NegativePosts
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        U.Id, U.DisplayName
),
PostComments AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.CreationDate) AS LastCommentDate
    FROM 
        Comments C
    GROUP BY 
        C.PostId
),
PostsWithComments AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        COALESCE(PC.CommentCount, 0) AS CommentCount,
        PC.LastCommentDate,
        @row_number := IF(@prev_user_id = P.OwnerUserId, @row_number + 1, 1) AS RN,
        @prev_user_id := P.OwnerUserId
    FROM 
        Posts P
    LEFT JOIN 
        PostComments PC ON P.Id = PC.PostId,
        (SELECT @row_number := 0, @prev_user_id := NULL) AS vars
    ORDER BY 
        P.OwnerUserId, P.CreationDate DESC
)
SELECT 
    U.UserId,
    U.DisplayName,
    U.TotalPosts,
    U.TotalUpVotes,
    U.TotalDownVotes,
    COALESCE(SUM(CASE WHEN PWC.RN = 1 THEN 1 ELSE 0 END), 0) AS LatestPostsCount,
    GROUP_CONCAT(PWC.Title ORDER BY PWC.CreationDate DESC SEPARATOR ', ') AS LatestPostTitles,
    AVG(PWC.Score) AS AveragePostScore,
    COUNT(DISTINCT PWC.PostId) AS DistinctPostsWithComments
FROM 
    UserStatistics U
LEFT JOIN 
    PostsWithComments PWC ON U.UserId = PWC.OwnerUserId
GROUP BY 
    U.UserId, U.DisplayName, U.TotalPosts, U.TotalUpVotes, U.TotalDownVotes
HAVING 
    U.TotalPosts > 0 OR U.TotalUpVotes > 0
ORDER BY 
    U.TotalUpVotes DESC, U.TotalDownVotes ASC;
