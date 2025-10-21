-- {"query": "57093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1350} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id ELSE NULL END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id ELSE NULL END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        MAX(P.LastActivityDate) AS LastPostActivityDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalPostScore,
        TotalQuestionScore,
        TotalAnswerScore,
        TotalComments,
        TotalVotes,
        LastPostActivityDate
    FROM
        UserActivity
    WHERE
        Reputation > 10000
    ORDER BY
        Reputation DESC
    LIMIT 100
),
RecentPosts AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.Tags,
        U.Id AS OwnerUserId,
        U.DisplayName AS OwnerDisplayName
    FROM
        Posts P
    JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE
        P.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopTags AS (
    SELECT
        T.TagName,
        T.Count AS TagCount,
        T.ExcerptPostId,
        T.WikiPostId,
        P.Title AS ExcerptPostTitle,
        WP.Title AS WikiPostTitle
    FROM
        Tags T
    LEFT JOIN
        Posts P ON T.ExcerptPostId = P.Id
    LEFT JOIN
        Posts WP ON T.WikiPostId = P.Id
    ORDER BY
        T.Count DESC
    LIMIT 50
),
PostVoteActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS CurrentScore,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(V.CreationDate) AS LastVoteDate
    FROM
        Posts P
    JOIN
        Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.Score
)
SELECT
    HU.UserId,
    HU.Reputation,
    HU.UserCreationDate,
    HU.TotalPosts,
    HU.TotalQuestions,
    HU.TotalAnswers,
    HU.TotalPostScore,
    HU.TotalQuestionScore,
    HU.TotalAnswerScore,
    HU.TotalComments,
    HU.TotalVotes,
    HU.LastPostActivityDate,
    RP.PostId,
    RP.PostTypeId,
    RP.PostCreationDate,
    RP.PostScore,
    RP.ViewCount,
    RP.AnswerCount,
    RP.CommentCount,
    RP.Tags,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    TT.TagName,
    TT.TagCount,
    TT.ExcerptPostTitle,
    TT.WikiPostTitle,
    PVA.CurrentScore,
    PVA.TotalVotes,
    PVA.UpVotes,
    PVA.DownVotes,
    PVA.LastVoteDate
FROM
    HighReputationUsers HU
LEFT JOIN
    RecentPosts RP ON HU.UserId = RP.OwnerUserId
LEFT JOIN
    TopTags TT ON RP.Tags LIKE CONCAT('%<', TT.TagName, '>%')
LEFT JOIN
    PostVoteActivity PVA ON RP.PostId = PVA.PostId
ORDER BY
    HU.Reputation DESC,
    RP.PostCreationDate DESC,
    TT.TagCount DESC,
    PVA.LastVoteDate DESC;