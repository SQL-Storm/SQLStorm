-- {"query": "27063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 2102} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentDate,
        MAX(V.CreationDate) AS LastVoteDate,
        MAX(B.Date) AS LastBadgeDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.DisplayName, U.CreationDate, U.LastAccessDate, U.Location
),
PostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        UA.UserId,
        UA.TotalPostScore,
        UA.TotalPosts,
        UA.TotalQuestions,
        UA.TotalAnswers,
        UA.TotalComments,
        UA.TotalVotes,
        UA.TotalBadges,
        LAG(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore,
        LEAD(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostScore,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS PostRank
    FROM
        Posts P
    JOIN
        UserActivity UA ON P.OwnerUserId = UA.UserId
    WHERE
        P.PostTypeId IN (1, 2)
),
TagMetrics AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagCount,
        P.PostTypeId,
        COUNT(P.Id) AS PostsContainingTag,
        SUM(P.Score) AS TotalScoreForTag,
        AVG(P.Score) AS AvgScoreForTag,
        MAX(P.Score) AS MaxScoreForTag,
        MIN(P.Score) AS MinScoreForTag,
        STRING_AGG(DISTINCT UA.DisplayName, ', ') AS UsersWithTag
    FROM
        Tags T
    JOIN
        Posts P ON T.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), ''><''))
    JOIN
        UserActivity UA ON P.OwnerUserId = UA.UserId
    GROUP BY
        T.Id, T.TagName, T.Count, P.PostTypeId
),
ComplexJoin AS (
    SELECT
        PM.PostId,
        PM.PostTypeId,
        PM.PostCreationDate,
        PM.Score AS PostScore,
        PM.ViewCount,
        PM.AnswerCount,
        PM.CommentCount,
        PM.FavoriteCount,
        PM.Title,
        PM.UserId,
        PM.TotalPostScore,
        PM.TotalPosts,
        PM.TotalQuestions,
        PM.TotalAnswers,
        PM.TotalComments,
        PM.TotalVotes,
        PM.TotalBadges,
        PM.PreviousPostScore,
        PM.NextPostScore,
        PM.PostRank,
        TM.TagId,
        TM.TagName,
        TM.TagCount,
        TM.PostsContainingTag,
        TM.TotalScoreForTag,
        TM.AvgScoreForTag,
        TM.MaxScoreForTag,
        TM.MinScoreForTag,
        TM.UsersWithTag,
        COALESCE(V.BountyAmount, 0) AS BountyAmount,
        V.VoteTypeId,
        V.CreationDate AS VoteCreationDate,
        C.Score AS CommentScore,
        C.Text AS CommentText,
        C.CreationDate AS CommentCreationDate,
        PH.PostHistoryTypeId,
        PH.CreationDate AS PostHistoryCreationDate,
        PH.UserId AS PostHistoryUserId,
        PH.Comment AS PostHistoryComment,
        PH.Text AS PostHistoryText,
        PL.RelatedPostId,
        PL.LinkTypeId,
        U.DisplayName AS PostHistoryUserDisplayName
    FROM
        PostMetrics PM
    LEFT JOIN
        TagMetrics TM ON PM.PostId = TM.PostId
    LEFT JOIN
        Votes V ON PM.PostId = V.PostId
    LEFT JOIN
        Comments C ON PM.PostId = C.PostId
    LEFT JOIN
        PostHistory PH ON PM.PostId = PH.PostId
    LEFT JOIN
        PostLinks PL ON PM.PostId = PL.PostId
    LEFT JOIN
        Users U ON PH.UserId = U.Id
    WHERE
        PM.PostTypeId IN (1, 2)
        AND (PM.Score > 0 OR PM.ViewCount > 100)
        AND (V.VoteTypeId IS NOT NULL OR C.Score IS NOT NULL OR PH.PostHistoryTypeId IS NOT NULL OR PL.LinkTypeId IS NOT NULL)
)
SELECT
    CJ.PostId,
    CJ.PostTypeId,
    CJ.PostCreationDate,
    CJ.PostScore,
    CJ.ViewCount,
    CJ.AnswerCount,
    CJ.CommentCount,
    CJ.FavoriteCount,
    CJ.Title,
    CJ.UserId,
    CJ.TotalPostScore,
    CJ.TotalPosts,
    CJ.TotalQuestions,
    CJ.TotalAnswers,
    CJ.TotalComments,
    CJ.TotalVotes,
    CJ.TotalBadges,
    CJ.PreviousPostScore,
    CJ.NextPostScore,
    CJ.PostRank,
    CJ.TagId,
    CJ.TagName,
    CJ.TagCount,
    CJ.PostsContainingTag,
    CJ.TotalScoreForTag,
    CJ.AvgScoreForTag,
    CJ.MaxScoreForTag,
    CJ.MinScoreForTag,
    CJ.UsersWithTag,
    CJ.BountyAmount,
    CJ.VoteTypeId,
    CJ.VoteCreationDate,
    CJ.CommentScore,
    CJ.CommentText,
    CJ.CommentCreationDate,
    CJ.PostHistoryTypeId,
    CJ.PostHistoryCreationDate,
    CJ.PostHistoryUserId,
    CJ.PostHistoryComment,
    CJ.PostHistoryText,
    CJ.RelatedPostId,
    CJ.LinkTypeId,
    CJ.PostHistoryUserDisplayName
FROM
    ComplexJoin CJ
WHERE
    CJ.PostCreationDate >= DATEADD(year, -1, GETDATE())
    AND (CJ.PostScore > 10 OR CJ.ViewCount > 500)
    AND (CJ.VoteTypeId IN (2, 3, 8) OR CJ.CommentScore IS NOT NULL OR CJ.PostHistoryTypeId IS NOT NULL OR CJ.LinkTypeId IS NOT NULL)
ORDER BY
    CJ.PostScore DESC,
    CJ.ViewCount DESC,
    CJ.PostCreationDate DESC
LIMIT 1000;
