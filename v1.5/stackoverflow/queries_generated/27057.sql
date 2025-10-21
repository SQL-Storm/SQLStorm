-- {"query": "27057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1585} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Location,
        COALESCE(U.Views, 0) AS UserViews,
        COALESCE(U.UpVotes, 0) AS UserUpVotes,
        COALESCE(U.DownVotes, 0) AS UserDownVotes,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(PH.CreationDate) AS LastEditDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    WHERE
        U.CreationDate >= DATEADD(year, -5, GETDATE())
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.LastAccessDate, U.Location, U.Views, U.UpVotes, U.DownVotes
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        U.DisplayName AS OwnerDisplayName,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        MAX(V.CreationDate) AS LastVoteDate,
        NTILE(4) OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserPostRank
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    WHERE
        P.CreationDate >= DATEADD(year, -3, GETDATE())
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.Title, P.Tags, P.AnswerCount, P.CommentCount, P.ClosedDate, P.CommunityOwnedDate, U.DisplayName
)
SELECT
   UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.DisplayName,
    UA.LastAccessDate,
    UA.Location,
    UA.UserViews,
    UA.UserUpVotes,
    UA.UserDownVotes,
    UA.TotalPosts,
    UA.TotalBadges,
    UA.TotalComments,
    UA.TotalUpvotesReceived,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.LastEditDate,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.Score,
    PA.ViewCount,
    PA.Title,
    PA.Tags,
    PA.AnswerCount,
    PA.CommentCount,
    PA.ClosedDate,
    PA.CommunityOwnedDate,
    PA.OwnerDisplayName,
    PA.TotalVotes,
    PA.TotalUpvotes,
    PA.TotalDownvotes,
    PA.LastVoteDate,
    PA.UserPostRank,
    CASE
        WHEN PA.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN PA.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS PostStatus,
    CONCAT(UA.DisplayName, ' (', UA.Location, ')') AS UserLocation,
    CASE
        WHEN PA.TotalUpvotes > PA.TotalDownvotes THEN 'Positive'
        WHEN PA.TotalUpvotes < PA.TotalDownvotes THEN 'Negative'
        ELSE 'Neutral'
    END AS VoteSentiment,
    COALESCE(LAG(PA.Score, 1) OVER (PARTITION BY PA.OwnerUserId ORDER BY PA.CreationDate), 0) AS PreviousPostScore,
    PA.Score - COALESCE(LAG(PA.Score, 1) OVER (PARTITION BY PA.OwnerUserId ORDER BY PA.CreationDate), 0) AS ScoreChange,
    LEAD(PA.Score, 1) OVER (PARTITION BY PA.OwnerUserId ORDER BY PA.CreationDate) AS NextPostScore,
    PA.Score - LEAD(PA.Score, 1) OVER (PARTITION BY PA.OwnerUserId ORDER BY PA.CreationDate) AS NextScoreChange,
    CASE
        WHEN PA.CommentCount > (SELECT AVG(CommentCount) FROM Posts) THEN 'High Engagement'
        WHEN PA.CommentCount < (SELECT AVG(CommentCount) FROM Posts) THEN 'Low Engagement'
        ELSE 'Average Engagement'
    END AS EngagementLevel
FROM
    UserActivity UA
LEFT JOIN
    PostActivity PA ON UA.UserId = PA.OwnerUserId
WHERE
    PA.UserPostRank IS NOT NULL
ORDER BY
    UA.Reputation DESC,
    PA.Score DESC,
    PA.CreationDate DESC;
