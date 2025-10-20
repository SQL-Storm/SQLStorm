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
PostTags AS (
    -- normalize tag strings into one row per post-tag
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        U.Id AS OwnerId,
        U.Reputation AS OwnerReputation,
        U.DisplayName AS OwnerDisplayName,
        Ttag AS TagName
    FROM
        Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    CROSS JOIN LATERAL (
        -- remove leading and trailing angle brackets and split by "><"
        SELECT TRIM(BOTH '<>' FROM P.Tags) AS tags_str
    ) ts
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(ts.tags_str, '\>\<') AS Ttag
    ) split ON TRUE
),
PostActivity AS (
    SELECT
        PT.PostId,
        PT.PostTypeId,
        PT.PostCreationDate,
        PT.Score,
        PT.ViewCount,
        PT.AnswerCount,
        PT.CommentCount,
        PT.FavoriteCount,
        PT.OwnerUserId,
        PT.OwnerReputation,
        PT.OwnerDisplayName,
        COUNT(DISTINCT C.Id) AS CommentCountOnPost,
        COUNT(DISTINCT V.Id) AS VoteCountOnPost,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountOnPost,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountOnPost,
        MIN(PT.TagName) AS AnyTagName -- keep a tag column to allow joining in next step if needed
    FROM
        PostTags PT
    LEFT JOIN
        Comments C ON PT.PostId = C.PostId
    LEFT JOIN
        Votes V ON PT.PostId = V.PostId
    GROUP BY
        PT.PostId, PT.PostTypeId, PT.PostCreationDate, PT.Score, PT.ViewCount, PT.AnswerCount, PT.CommentCount, PT.FavoriteCount, PT.OwnerUserId, PT.OwnerReputation, PT.OwnerDisplayName
),
TagActivity AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagCount,
        COUNT(DISTINCT PT.PostId) AS PostsWithTag,
        SUM(PT.Score) AS TotalScoreForTag,
        SUM(PT.ViewCount) AS TotalViewsForTag,
        COUNT(DISTINCT C.Id) AS CommentsOnTag,
        COUNT(DISTINCT V.Id) AS VotesOnTag,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnTag,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnTag
    FROM
        Tags T
    LEFT JOIN
        PostTags PT ON PT.TagName = T.TagName
    LEFT JOIN
        Comments C ON PT.PostId = C.PostId
    LEFT JOIN
        Votes V ON PT.PostId = V.PostId
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
    TagActivity TA ON TA.TagName = (SELECT MIN(TagName) FROM PostTags WHERE PostId = PA.PostId)
WHERE
    UA.TotalPosts > 100
    AND PA.PostCreationDate >= DATE '2022-01-01'
    AND TA.PostsWithTag > 50
ORDER BY
    PA.Score DESC,
    TA.TotalScoreForTag DESC
LIMIT 100;