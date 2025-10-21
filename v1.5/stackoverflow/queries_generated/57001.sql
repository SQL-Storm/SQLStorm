-- {"query": "57001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1312} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        SUM(C.Score) AS TotalCommentScore,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.LastActivityDate,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId,
        U.DisplayName, P.LastActivityDate
),
TagStatistics AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagCount,
        COUNT(P.Id) AS PostsWithTag,
        SUM(P.Score) AS TotalScoreForTaggedPosts,
        SUM(P.ViewCount) AS TotalViewsForTaggedPosts,
        AVG(P.Score) AS AverageScoreForTaggedPosts,
        AVG(P.ViewCount) AS AverageViewsForTaggedPosts,
        EXTRACT(YEAR FROM P.CreationDate) AS Year,
        EXTRACT(MONTH FROM P.CreationDate) AS Month
    FROM
        Tags T
    LEFT JOIN
        Posts P ON T.TagName = ANY(STRING_TO_ARRAY(P.Tags, ''><''))
    GROUP BY
        T.Id, T.TagName, T.Count, Year, Month
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalPostScore,
    UA.TotalCommentScore,
    UA.LastPostActivity,
    UA.LastCommentDate,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.PostScore,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCount,
    PA.FavoriteCount,
    PA.OwnerUserId,
    PA.OwnerDisplayName,
    PA.LastActivityDate,
    PA.TotalVotes,
    PA.TotalUpVotes,
    PA.TotalDownVotes,
    PA.TotalBountyAmount,
    TS.TagId,
    TS.TagName,
    TS.TagCount,
    TS.PostsWithTag,
    TS.TotalScoreForTaggedPosts,
    TS.TotalViewsForTaggedPosts,
    TS.AverageScoreForTaggedPosts,
    TS.AverageViewsForTaggedPosts,
    TS.Year,
    TS.Month
FROM
    UserActivity UA
LEFT JOIN
    PostActivity PA ON UA.UserId = PA.OwnerUserId
LEFT JOIN
    TagStatistics TS ON PA.PostId = ANY(ARRAY(SELECT P.Id FROM Posts P WHERE TS.TagName = ANY(STRING_TO_ARRAY(P.Tags, ''><''))))
WHERE
    UA.TotalPosts > 0 OR UA.TotalComments > 0
ORDER BY
    UA.Reputation DESC,
    PA.PostScore DESC,
    TS.TotalScoreForTaggedPosts DESC
LIMIT 1000;
