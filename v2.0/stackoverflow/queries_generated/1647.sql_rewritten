-- {"query": "1647.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2073} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MIN(P.CreationDate) AS FirstPostCreation,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViews,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT P.Id) > 0
),
PostEventSummary AS (
    WITH RawPostEvents AS (
        SELECT
            PostId,
            CreationDate,
            PostHistoryTypeId,
            'Edit' AS EventType
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        UNION ALL
        SELECT
            PostId,
            CreationDate,
            PostHistoryTypeId,
            'Close' AS EventType
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        UNION ALL
        SELECT
            PostId,
            CreationDate,
            PostHistoryTypeId,
            'Reopen' AS EventType
        FROM PostHistory
        WHERE PostHistoryTypeId = 11
        UNION ALL
        SELECT
            PostId,
            CreationDate,
            PostHistoryTypeId,
            'Delete' AS EventType
        FROM PostHistory
        WHERE PostHistoryTypeId = 12
    )
    SELECT
        PostId,
        COUNT(CASE WHEN EventType = 'Edit' THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN EventType = 'Close' THEN 1 ELSE NULL END) AS CloseCount,
        COUNT(CASE WHEN EventType = 'Reopen' THEN 1 ELSE NULL END) AS ReopenCount,
        COUNT(CASE WHEN EventType = 'Delete' THEN 1 ELSE NULL END) AS DeleteCount,
        MAX(CASE WHEN EventType = 'Close' THEN CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN EventType = 'Reopen' THEN CreationDate ELSE NULL END) AS LastReopenedDate,
        MIN(CreationDate) AS FirstHistoryEventDate,
        MAX(CreationDate) AS LastHistoryEventDate
    FROM RawPostEvents
    GROUP BY PostId
),
TagStats AS (
    SELECT
        T.TagName,
        T.Count AS TagUseCount,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueContributors
    FROM Tags T
    JOIN Posts P ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    WHERE P.PostTypeId = 1
    GROUP BY T.TagName, T.Count
    HAVING COUNT(P.Id) > 50
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.LastActivityDate,
        P.ClosedDate,
        SUBSTRING(P.Body, 1, 100) AS BodySnippet,
        COALESCE(P.Title, 'N/A') AS PostTitle,
        PES.EditCount,
        PES.CloseCount,
        PES.ReopenCount,
        PES.DeleteCount,
        PES.LastClosedDate,
        PES.LastReopenedDate,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreInType,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId) AS AvgOwnerPostScore,
        SUM(P.ViewCount) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS CumulativeOwnerViews,
        (SELECT COUNT(Q.Id) FROM Posts Q WHERE Q.AcceptedAnswerId = P.Id) AS IsAcceptedAnswerForCount,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDaysAtLastActivity,
        CAST(P.FavoriteCount AS NUMERIC) / NULLIF(P.ViewCount, 0) AS FavoriteToViewRatio
    FROM Posts P
    LEFT JOIN PostEventSummary PES ON P.Id = PES.PostId
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate >= '2020-01-01'
      AND P.Score > 0
)
SELECT
    UA.DisplayName,
    UA.Reputation,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalPostViews,
    UA.TotalPostScore,
    UA.TotalFavoriteCount,
    UA.TotalComments,
    UA.TotalCommentScore,
    UA.GoldBadges,
    UA.SilverBadges,
    UA.BronzeBadges,
    PD.PostId,
    PD.PostTitle,
    PD.PostScore,
    PD.PostViewCount,
    PD.PostFavoriteCount,
    PD.AnswerCount,
    PD.PostCommentCount,
    PD.BodySnippet,
    PD.EditCount,
    PD.CloseCount,
    PD.ReopenCount,
    PD.DeleteCount,
    PD.LastClosedDate,
    PD.LastReopenedDate,
    PD.PostAgeDaysAtLastActivity,
    PD.FavoriteToViewRatio,
    PD.RankByScoreInType,
    PD.AvgOwnerPostScore,
    PD.CumulativeOwnerViews,
    PD.IsAcceptedAnswerForCount,
    (SELECT TS.TagName FROM TagStats TS WHERE PD.PostTitle LIKE '%' || TS.TagName || '%' ORDER BY TS.TagUseCount DESC LIMIT 1) AS MostPopularRelatedTag,
    CASE
        WHEN PD.CloseCount > 0 AND PD.ReopenCount > 0 THEN 'Closed & Reopened'
        WHEN PD.CloseCount > 0 THEN 'Closed'
        WHEN PD.DeleteCount > 0 THEN 'Deleted At Least Once'
        WHEN PD.EditCount > 5 AND PD.PostScore < 0 THEN 'Heavily Edited & Negative Score'
        WHEN PD.PostViewCount > 10000 AND PD.PostFavoriteCount > 100 THEN 'Highly Engaged'
        ELSE 'Regular'
    END AS PostStatusCategory,
    AGE(cast('2024-10-01 12:34:56' as timestamp), UA.UserCreationDate) AS UserAccountAge,
    (
        SELECT
            AVG(V.BountyAmount)
        FROM Votes V
        WHERE V.PostId = PD.PostId
          AND V.VoteTypeId IN (8, 9)
          AND V.BountyAmount IS NOT NULL
    ) AS AvgBountyAmountForPost
FROM UserActivity UA
JOIN PostDetailsExtended PD ON UA.UserId = PD.OwnerUserId
WHERE UA.Reputation > 5000
  AND (PD.EditCount > 2 OR PD.CloseCount > 0 OR PD.ReopenCount > 0 OR PD.DeleteCount > 0 OR PD.PostScore > 500 OR PD.PostViewCount > 50000)
  AND PD.PostTypeId IN (1, 2)
  AND PD.IsAcceptedAnswerForCount > 0
ORDER BY UA.Reputation DESC, PD.PostScore DESC, PD.LastActivityDate DESC
LIMIT 1000;