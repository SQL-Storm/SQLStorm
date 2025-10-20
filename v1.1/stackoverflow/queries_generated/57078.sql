-- {"query": "57078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1476} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AnswerScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.Id AS OwnerUserId,
        U.Reputation AS OwnerReputation,
        U.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT C.Id) AS CommentCountOnPost,
        COUNT(DISTINCT V.Id) AS VoteCountOnPost,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountOnPost,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountOnPost
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, U.Id, U.Reputation, U.DisplayName
),
TagActivity AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagCount,
        COUNT(P.Id) AS PostsWithTag,
        SUM(P.Score) AS TotalScoreForTag,
        SUM(P.ViewCount) AS TotalViewsForTag,
        COUNT(DISTINCT C.Id) AS CommentsOnTag,
        COUNT(DISTINCT V.Id) AS VotesOnTag,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnTag,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnTag
    FROM
        Tags T
    LEFT JOIN
        Posts P ON T.Id = ANY(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), ''><''))
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    GROUP BY
        T.Id, T.TagName, T.Count
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.QuestionScore,
    UA.AnswerScore,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalUpVotes,
    UA.TotalDownVotes,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.Score AS PostScore,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCountOnPost,
    PA.VoteCountOnPost,
    PA.UpVoteCountOnPost,
    PA.DownVoteCountOnPost,
    TA.TagId,
    TA.TagName,
    TA.TagCount,
    TA.PostsWithTag,
    TA.TotalScoreForTag,
    TA.TotalViewsForTag,
    TA.CommentsOnTag,
    TA.VotesOnTag,
    TA.UpVotesOnTag,
    TA.DownVotesOnTag
FROM
    UserActivity UA
JOIN
    PostActivity PA ON UA.UserId = PA.OwnerUserId
JOIN
    TagActivity TA ON TA.TagId = ANY(string_to_array(substring(PA.Tags, 2, length(PA.Tags)-2), ''><''))
WHERE
    UA.TotalPosts > 100
    AND PA.PostCreationDate >= '2022-01-01'
    AND TA.PostsWithTag > 50
ORDER BY
    PA.Score DESC,
    TA.TotalScoreForTag DESC
LIMIT 100;
 