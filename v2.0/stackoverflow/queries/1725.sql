-- {"query": "1725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3306}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END), 0.0) AS AvgQuestionScoreByOwner,
        MAX(U.LastAccessDate) AS LastUserAccessDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    WHERE U.Reputation > 500
      AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' YEAR)
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(P.Id) > 0 OR COUNT(C.Id) > 0 OR SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) > 0
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        COALESCE(P.Score, 0) AS PostScore,
        COALESCE(P.ViewCount, 0) AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - P.LastActivityDate)) / 86400) AS DaysSinceLastActivity,
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        CASE WHEN P.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed,
        P.ClosedDate,
        COALESCE(
            NULLIF(
                TRIM(
                    SPLIT_PART(
                        SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><', 1
                    )
                ),
                ''
            ),
            'no-primary-tag'
        ) AS PrimaryTag,
        (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, '<code>', ''))) / 5 AS CodeSnippetCount,
        (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, 'http', ''))) / 4 AS LinkCountInBody
    FROM Posts P
    WHERE P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' YEAR)
      AND P.Body IS NOT NULL
      AND (P.PostTypeId = 1 OR (P.PostTypeId = 2 AND P.ParentId IS NOT NULL))
),
PostHistoryInsights AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEvents,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS LastCloseReasonId,
        (SELECT COUNT(DISTINCT PL.RelatedPostId)
         FROM PostLinks PL
         WHERE PL.PostId = PH.PostId AND PL.LinkTypeId = 3) AS DuplicateLinkCount,
        (SELECT MAX(V.CreationDate)
         FROM Votes V
         WHERE V.PostId = PH.PostId AND V.VoteTypeId = 2) AS LatestUpVoteDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11)
    GROUP BY PH.PostId
),
TagPerformance AS (
    SELECT
        T.TagName,
        T.Id AS TagId,
        T.Count AS TotalPostsWithTag,
        COALESCE(SUM(P.ViewCount), 0) AS TotalTagViewsAggregated,
        COALESCE(AVG(P.Score), 0.0) AS AvgQuestionScoreInTagAggregated,
        COALESCE(AVG(P.AnswerCount), 0.0) AS AvgAnswersPerQuestionInTagAggregated,
        COALESCE(MAX(P.CreationDate), CAST('1900-01-01' AS TIMESTAMP)) AS LatestQuestionInTag
    FROM Tags T
    LEFT JOIN Posts P ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%' AND P.PostTypeId = 1 AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' YEAR)
    WHERE T.Count > 50
    GROUP BY T.TagName, T.Id, T.Count
),
RankedPosts AS (
    SELECT
        PEM.PostId,
        PEM.PostTypeId,
        PEM.Title,
        PEM.PostScore,
        PEM.PostViewCount,
        PEM.PostAnswerCount,
        PEM.PostCommentCount,
        PEM.PostFavoriteCount,
        PEM.PostCreationDate,
        PEM.LastActivityDate,
        PEM.DaysSinceLastActivity,
        PEM.HasAcceptedAnswer,
        PEM.IsClosed,
        PEM.ClosedDate,
        PEM.PrimaryTag,
        PEM.CodeSnippetCount,
        PEM.LinkCountInBody,
        UAS.DisplayName AS OwnerDisplayName,
        UAS.Reputation AS OwnerReputation,
        UAS.UserCreationDate AS OwnerCreationDate,
        PHI.EditCount,
        PHI.CloseEvents,
        PHI.ReopenEvents,
        PHI.FirstEditDate,
        PHI.LastCloseReasonId,
        PHI.DuplicateLinkCount,
        PHI.LatestUpVoteDate,
        TP.TotalTagViewsAggregated,
        TP.AvgQuestionScoreInTagAggregated,
        TP.AvgAnswersPerQuestionInTagAggregated,
        DENSE_RANK() OVER (PARTITION BY PEM.PrimaryTag ORDER BY PEM.PostScore DESC, PEM.PostViewCount DESC) AS RankInTagByScoreViews,
        ROW_NUMBER() OVER (PARTITION BY UAS.UserId ORDER BY PEM.PostCreationDate DESC) AS UserPostSeqNum,
        LAG(PEM.PostCreationDate, 1, CAST('1900-01-01' AS TIMESTAMP)) OVER (PARTITION BY UAS.UserId ORDER BY PEM.PostCreationDate) AS PreviousPostDate
    FROM PostEngagementMetrics PEM
    INNER JOIN UserActivitySummary UAS ON PEM.OwnerUserId = UAS.UserId
    LEFT JOIN PostHistoryInsights PHI ON PEM.PostId = PHI.PostId
    LEFT JOIN TagPerformance TP ON PEM.PrimaryTag = TP.TagName
    WHERE PEM.PostTypeId = 1
)
SELECT
    RP.PostId,
    RP.PostTypeId,
    RP.Title,
    RP.OwnerDisplayName,
    RP.OwnerReputation,
    RP.PostScore,
    RP.PostViewCount,
    RP.PostAnswerCount,
    RP.PostCommentCount,
    RP.PostFavoriteCount,
    RP.PostCreationDate,
    RP.LastActivityDate,
    RP.DaysSinceLastActivity,
    RP.HasAcceptedAnswer,
    RP.IsClosed,
    RP.PrimaryTag,
    RP.CodeSnippetCount,
    RP.LinkCountInBody,
    RP.EditCount,
    RP.CloseEvents,
    RP.ReopenEvents,
    RP.DuplicateLinkCount,
    RP.RankInTagByScoreViews,
    (EXTRACT(EPOCH FROM (RP.PostCreationDate - RP.PreviousPostDate)) / 86400) AS DaysBetweenPosts,
    (SELECT VT.Name FROM VoteTypes VT WHERE VT.Id = (
        SELECT V.VoteTypeId FROM Votes V WHERE V.PostId = RP.PostId ORDER BY V.CreationDate DESC LIMIT 1
    )) AS LatestVoteTypeName,
    COALESCE(RP.TotalTagViewsAggregated, 0) AS TotalTagViews,
    COALESCE(RP.AvgQuestionScoreInTagAggregated, 0.0) AS AvgTagScore
FROM RankedPosts RP
WHERE RP.PostTypeId = 1
  AND RP.RankInTagByScoreViews <= 10
  AND RP.DaysSinceLastActivity < 365
  AND RP.PostScore >= 50
  AND RP.PostAnswerCount >= 3
  AND RP.HasAcceptedAnswer IS TRUE
  AND RP.CodeSnippetCount > 0
  AND RP.LinkCountInBody > 0
  AND RP.OwnerReputation > 1000
  AND LOWER(RP.Title) LIKE '%performance%'
  AND RP.LatestUpVoteDate IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM PostHistory PHC
      JOIN PostHistoryTypes PHT ON PHC.PostHistoryTypeId = PHT.Id
      WHERE PHC.PostId = RP.PostId AND PHT.Name = 'Post Deleted'
  )
  AND (
        (RP.IsClosed IS FALSE)
        OR (RP.IsClosed IS TRUE AND RP.ReopenEvents > 0)
        OR (RP.IsClosed IS TRUE AND RP.LastCloseReasonId IS NOT NULL AND RP.LastCloseReasonId NOT IN ('2', '3'))
      )
UNION ALL
SELECT
    RP_Closed.PostId,
    RP_Closed.PostTypeId,
    RP_Closed.Title,
    RP_Closed.OwnerDisplayName,
    RP_Closed.OwnerReputation,
    RP_Closed.PostScore,
    RP_Closed.PostViewCount,
    RP_Closed.PostAnswerCount,
    RP_Closed.PostCommentCount,
    RP_Closed.PostFavoriteCount,
    RP_Closed.PostCreationDate,
    RP_Closed.LastActivityDate,
    RP_Closed.DaysSinceLastActivity,
    RP_Closed.HasAcceptedAnswer,
    RP_Closed.IsClosed,
    RP_Closed.PrimaryTag,
    RP_Closed.CodeSnippetCount,
    RP_Closed.LinkCountInBody,
    RP_Closed.EditCount,
    RP_Closed.CloseEvents,
    RP_Closed.ReopenEvents,
    RP_Closed.DuplicateLinkCount,
    RP_Closed.RankInTagByScoreViews,
    (EXTRACT(EPOCH FROM (RP_Closed.PostCreationDate - RP_Closed.PreviousPostDate)) / 86400) AS DaysBetweenPosts,
    (SELECT VT.Name FROM VoteTypes VT WHERE VT.Id = (
        SELECT V.VoteTypeId FROM Votes V WHERE V.PostId = RP_Closed.PostId ORDER BY V.CreationDate DESC LIMIT 1
    )) AS LatestVoteTypeName,
    COALESCE(RP_Closed.TotalTagViewsAggregated, 0) AS TotalTagViews,
    COALESCE(RP_Closed.AvgQuestionScoreInTagAggregated, 0.0) AS AvgTagScore
FROM RankedPosts RP_Closed
WHERE RP_Closed.PostTypeId = 1
  AND RP_Closed.IsClosed IS TRUE
  AND RP_Closed.ClosedDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR)
  AND RP_Closed.EditCount >= 5
  AND RP_Closed.CloseEvents >= 1
  AND RP_Closed.ReopenEvents = 0
  AND RP_Closed.PostScore < 20
  AND RP_Closed.DuplicateLinkCount > 0
  AND RP_Closed.OwnerReputation BETWEEN 500 AND 5000
  AND RP_Closed.PrimaryTag IN ('java', 'c#', 'python', 'javascript')
  AND RP_Closed.CodeSnippetCount > 1
ORDER BY PostCreationDate DESC, PostScore DESC
LIMIT 500;