WITH UserActivity AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(DISTINCT P.Id) AS TotalPosts, 
        SUM(CASE WHEN VT.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN VT.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes VT ON P.Id = VT.PostId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName
),
PostInteraction AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT PL.Id) AS LinkCount,
        COUNT(DISTINCT V.Id) AS VoteCount,
        COUNT(DISTINCT PH.Id) AS HistoryCount
    FROM 
        Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    GROUP BY 
        P.Id, P.Title
)
SELECT 
    UA.UserId, 
    UA.DisplayName, 
    UA.TotalPosts, 
    UA.UpVotesReceived, 
    UA.DownVotesReceived, 
    UA.TotalComments, 
    UA.GoldBadges, 
    UA.SilverBadges, 
    UA.BronzeBadges,
    AVG(PI.CommentCount) AS AvgCommentsPerPost,
    AVG(PI.LinkCount) AS AvgLinksPerPost,
    AVG(PI.VoteCount) AS AvgVotesPerPost,
    AVG(PI.HistoryCount) AS AvgHistoryEntriesPerPost
FROM 
    UserActivity UA
INNER JOIN 
    Posts P ON UA.UserId = P.OwnerUserId
INNER JOIN 
    PostInteraction PI ON P.Id = PI.PostId
GROUP BY 
    UA.UserId, UA.DisplayName, UA.TotalPosts, UA.UpVotesReceived, UA.DownVotesReceived, 
    UA.TotalComments, UA.GoldBadges, UA.SilverBadges, UA.BronzeBadges
ORDER BY 
    UA.TotalPosts DESC, UA.UpVotesReceived DESC
LIMIT 100;