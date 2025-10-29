WITH ActiveUserStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(P.Score) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0) AS AvgPostScore,
        COUNT(C.Id) AS TotalCommentsMade,
        COALESCE(SUM(LENGTH(C.Text)), 0) AS TotalCommentChars,
        MAX(U.LastAccessDate) AS UserLastActivity,
        NTILE(5) OVER (ORDER BY U.Reputation DESC, COUNT(P.Id) DESC) AS ReputationQuintile
    FROM Users U
    INNER JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation >= 1000
      AND U.LastAccessDate >= DATE_TRUNC('year', CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - INTERVAL '1 year'
      AND U.DisplayName IS NOT NULL
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.LastAccessDate
    HAVING COUNT(P.Id) > 10
),
PostDetailsRaw AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.LastEditDate,
        P.AcceptedAnswerId,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(COALESCE(P.Title, '')) AS TitleLength,
        REPLACE(REPLACE(REPLACE(LOWER(COALESCE(P.Tags, '')), '<sql>', ''), '<database>', ''), '<performance>', '') AS CleanedTags,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UniqueUpVoters
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= DATE_TRUNC('year', CAST('2024-10-01 12:34:56' AS TIMESTAMP)) - INTERVAL '3 year'
),
PostEngagementMetrics AS (
    SELECT
        PDR.PostId,
        PDR.PostTypeId,
        PDR.OwnerUserId,
        PDR.PostCreationDate,
        PDR.PostScore,
        PDR.ViewCount,
        PDR.AnswerCount,
        PDR.PostCommentCount,
        PDR.PostFavoriteCount,
        PDR.AcceptedAnswerId,
        PDR.ClosedDate,
        PDR.BodyLength,
        PDR.TitleLength,
        PDR.CleanedTags,
        PDR.UniqueUpVoters,
        (CASE WHEN PDR.ViewCount > 0 THEN CAST(PDR.PostScore AS NUMERIC) / PDR.ViewCount ELSE 0 END) AS ScorePerViewRatio,
        COALESCE(C_agg.AvgCommentLength, 0) AS AvgCommentLengthOnPost,
        COALESCE(C_agg.DistinctCommenters, 0) AS DistinctCommentersOnPost,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesOnPost,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesOnPost
    FROM PostDetailsRaw PDR
    LEFT JOIN (
        SELECT
            C.PostId,
            AVG(LENGTH(C.Text)) AS AvgCommentLength,
            COUNT(DISTINCT C.UserId) AS DistinctCommenters
        FROM Comments C
        GROUP BY C.PostId
    ) C_agg ON PDR.PostId = C_agg.PostId
    LEFT JOIN Votes V ON PDR.PostId = V.PostId
    GROUP BY
        PDR.PostId, PDR.PostTypeId, PDR.OwnerUserId, PDR.PostCreationDate, PDR.PostScore, PDR.ViewCount, PDR.AnswerCount,
        PDR.PostCommentCount, PDR.PostFavoriteCount, PDR.AcceptedAnswerId, PDR.ClosedDate, PDR.BodyLength,
        PDR.TitleLength, PDR.CleanedTags, PDR.UniqueUpVoters, C_agg.AvgCommentLength, C_agg.DistinctCommenters
),
PostEditAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.UserId) AS DistinctEditors,
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastCloseDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY PH.PostId
    HAVING COUNT(DISTINCT PH.UserId) > 1 OR SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) > 2
),
HighPerformingPosts AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        'Question' AS PostTypeCategory,
        PEM.PostScore,
        PEM.ViewCount,
        PEM.PostCommentCount,
        PEM.AnswerCount,
        PEM.ScorePerViewRatio,
        PEM.CleanedTags,
        COALESCE(PEA.EditCount, 0) AS EditActivityScore,
        PEM.PostCreationDate
    FROM PostEngagementMetrics PEM
    LEFT JOIN PostEditAnalysis PEA ON PEM.PostId = PEA.PostId
    WHERE PEM.PostTypeId = 1
      AND PEM.ViewCount > 5000
      AND PEM.AcceptedAnswerId IS NOT NULL
      AND PEM.PostCommentCount >= 5
      AND PEM.ScorePerViewRatio >= 0.005
      AND PEM.CleanedTags LIKE '%java%'
),
InfluentialAnswers AS (
    SELECT
        PEM.PostId,
        PEM.OwnerUserId,
        'Answer' AS PostTypeCategory,
        PEM.PostScore,
        (SELECT PQ.ViewCount FROM Posts PQ WHERE PQ.Id = P_ans.ParentId) AS ParentQuestionViewCount,
        PEM.PostCommentCount,
        (SELECT PQ.AnswerCount FROM Posts PQ WHERE PQ.Id = P_ans.ParentId) AS ParentQuestionAnswerCount,
        PEM.ScorePerViewRatio,
        PEM.CleanedTags,
        COALESCE(PEA.EditCount, 0) AS EditActivityScore,
        PEM.PostCreationDate
    FROM PostEngagementMetrics PEM
    INNER JOIN Posts P_ans ON PEM.PostId = P_ans.Id AND P_ans.PostTypeId = 2
    LEFT JOIN PostEditAnalysis PEA ON PEM.PostId = PEA.PostId
    WHERE PEM.PostTypeId = 2
      AND PEM.PostScore > 50
      AND (SELECT PQ.AnswerCount FROM Posts PQ WHERE PQ.Id = P_ans.ParentId) > 10
      AND PEM.OwnerUserId IN (SELECT AUS.UserId FROM ActiveUserStats AUS WHERE AUS.Reputation > 10000)
      AND NOT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = PEM.OwnerUserId AND B.Name = 'Disciplined')
)
SELECT
    AUS.DisplayName,
    AUS.Reputation,
    AUS.ReputationQuintile,
    CombinedPosts.PostId,
    CombinedPosts.PostTypeCategory,
    CombinedPosts.PostScore,
    CombinedPosts.ViewCount,
    CombinedPosts.PostCommentCount,
    CombinedPosts.AnswerCount,
    CombinedPosts.ScorePerViewRatio,
    COALESCE(CombinedPosts.CleanedTags, 'no_tags') AS ProcessedTags,
    CombinedPosts.EditActivityScore,
    AVG(CombinedPosts.PostScore) OVER (PARTITION BY AUS.ReputationQuintile) AS AvgScoreInReputationQuintile,
    RANK() OVER (PARTITION BY CombinedPosts.PostTypeCategory ORDER BY CombinedPosts.PostScore DESC, CombinedPosts.ViewCount DESC) AS RankWithinCategory,
    SUM(CombinedPosts.PostScore + CombinedPosts.EditActivityScore * 5 + CombinedPosts.PostCommentCount * 2)
        OVER (PARTITION BY AUS.UserId ORDER BY CombinedPosts.PostCreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS UserCumulativeEngagementScore,
    CASE
        WHEN CombinedPosts.PostTypeCategory = 'Question' AND CombinedPosts.AnswerCount > 0 THEN 'Answered Question'
        WHEN CombinedPosts.PostTypeCategory = 'Question' AND CombinedPosts.AnswerCount = 0 THEN 'Unanswered Question'
        WHEN CombinedPosts.PostTypeCategory = 'Answer' THEN 'Provided Answer'
        ELSE 'Uncategorized'
    END AS PostStatusClassifier,
    (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = AUS.UserId AND B.Class = 1) AS GoldBadgeCount
FROM ActiveUserStats AUS
INNER JOIN (
    SELECT PostId, OwnerUserId, PostTypeCategory, PostScore, ViewCount, PostCommentCount, AnswerCount, ScorePerViewRatio, CleanedTags, EditActivityScore, PostCreationDate
    FROM HighPerformingPosts
    UNION ALL
    SELECT PostId, OwnerUserId, PostTypeCategory, PostScore, ParentQuestionViewCount AS ViewCount, PostCommentCount, ParentQuestionAnswerCount AS AnswerCount, ScorePerViewRatio, CleanedTags, EditActivityScore, PostCreationDate
    FROM InfluentialAnswers
) CombinedPosts ON AUS.UserId = CombinedPosts.OwnerUserId
WHERE AUS.TotalPosts > 20
  AND COALESCE(CombinedPosts.CleanedTags, '') LIKE '%python%'
  AND CombinedPosts.PostScore > (
      SELECT AVG(PEM.PostScore)
      FROM PostEngagementMetrics PEM
      WHERE PEM.PostTypeId = CASE WHEN CombinedPosts.PostTypeCategory = 'Question' THEN 1 ELSE 2 END
  )
GROUP BY
    AUS.DisplayName,
    AUS.Reputation,
    AUS.ReputationQuintile,
    AUS.UserId,
    CombinedPosts.PostId,
    CombinedPosts.PostTypeCategory,
    CombinedPosts.PostScore,
    CombinedPosts.ViewCount,
    CombinedPosts.PostCommentCount,
    CombinedPosts.AnswerCount,
    CombinedPosts.ScorePerViewRatio,
    CombinedPosts.CleanedTags,
    CombinedPosts.EditActivityScore,
    CombinedPosts.PostCreationDate
ORDER BY AUS.Reputation DESC, UserCumulativeEngagementScore DESC, RankWithinCategory ASC
LIMIT 1000;