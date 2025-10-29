WITH UserEngagementRanked AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadgesCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        (
            SELECT COUNT(P.Id)
            FROM Posts AS P
            WHERE P.OwnerUserId = U.Id
              AND P.PostTypeId = 1
              AND P.Score > 50
              AND P.CreationDate >= U.CreationDate + INTERVAL '1 year'
              AND P.ViewCount > 5000
        ) AS HighImpactQuestionsPostFirstYear,
        NTILE(10) OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationDecile,
        RANK() OVER (ORDER BY U.LastAccessDate DESC, U.Reputation DESC) AS LatestActiveUserRank
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.LastAccessDate
),
PostVersionAnalysis AS (
    SELECT
        PH.PostId,
        PH.Id AS HistoryId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryEditorUserId,
        PH.Text AS CurrentHistoryText,
        LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryText,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_history_for_post
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (2, 5, 8)
      AND PH.Text IS NOT NULL
),
PostDetailWithTagsAndLinks AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.LastEditDate,
        COALESCE(P.ClosedDate, TIMESTAMP '9999-12-31 00:00:00') AS EffectiveClosedDate,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfPostsCount,
        AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PL.CreationDate))) / 86400.0 AS AvgLinkAgeDays,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        P.ParentId
    FROM Posts AS P
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '6 year'
      AND P.Score > 0
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.Title, P.Tags, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.LastEditDate, P.ClosedDate, P.ParentId
),
CommentMetrics AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(DISTINCT C.UserId) AS UniqueCommenters,
        MAX(C.CreationDate) AS LastCommentDate
    FROM Comments AS C
    GROUP BY C.PostId
)
SELECT
    UER.DisplayName AS OwnerUserName,
    UER.Reputation,
    UER.ReputationDecile,
    UER.GoldBadgesCount,
    PDA.PostId,
    PDA.Title AS PostTitle,
    PDA.PostCreationDate,
    PDA.PostScore,
    PDA.ViewCount,
    PDA.FavoriteCount,
    PDA.EffectiveClosedDate,
    PDA.TagName,
    T.Count AS TagPopularity,
    PVA.HistoryEditorUserId AS LastEditorId,
    PVA.HistoryDate AS LastEditHistoryDate,
    LENGTH(PVA.CurrentHistoryText) - LENGTH(PVA.PreviousHistoryText) AS BodyTextChangeLength,
    PDA.LinkedPostsCount,
    PDA.DuplicateOfPostsCount,
    COALESCE(PDA.AvgLinkAgeDays, 0.0) AS AverageRelatedLinkAgeDays,
    CM.TotalComments,
    CM.TotalCommentScore,
    CM.UniqueCommenters,
    NULLIF(UER.UpVotes, 0) / NULLIF(UER.DownVotes, 1) AS OwnerUpDownVoteRatio,
    PERCENT_RANK() OVER (PARTITION BY UER.ReputationDecile ORDER BY PDA.PostScore DESC, PDA.ViewCount DESC) AS PostScoreRankInDecile,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes AS V WHERE V.PostId = PDA.PostId AND V.VoteTypeId = 5) AS NumberOfFavoriters
FROM PostDetailWithTagsAndLinks AS PDA
INNER JOIN UserEngagementRanked AS UER ON PDA.OwnerUserId = UER.UserId
INNER JOIN PostVersionAnalysis AS PVA ON PDA.PostId = PVA.PostId
LEFT JOIN Tags AS T ON PDA.TagName = T.TagName
LEFT JOIN CommentMetrics AS CM ON PDA.PostId = CM.PostId
WHERE PVA.rn_latest_history_for_post = 1
  AND UER.ReputationDecile <= 3
  AND PDA.PostTypeId = 1
  AND (PDA.EffectiveClosedDate = TIMESTAMP '9999-12-31 00:00:00' OR PDA.EffectiveClosedDate > CAST('2024-10-01' AS date) - INTERVAL '1 year')
  AND (ABS(LENGTH(PVA.CurrentHistoryText) - LENGTH(PVA.PreviousHistoryText)) > 100 OR PVA.PreviousHistoryText = '')
  AND (PDA.TagName IS NOT NULL AND T.Count > 5000)
  AND UER.HighImpactQuestionsPostFirstYear > 3
  AND CM.TotalComments IS NOT NULL AND CM.TotalComments > 5
  AND PDA.PostCreationDate BETWEEN UER.CreationDate AND UER.CreationDate + INTERVAL '5 year'
GROUP BY
    UER.DisplayName, UER.Reputation, UER.ReputationDecile, UER.GoldBadgesCount, PDA.PostId, PDA.Title, PDA.PostCreationDate,
    PDA.PostScore, PDA.ViewCount, PDA.FavoriteCount, PDA.EffectiveClosedDate, PDA.TagName, T.Count,
    PVA.HistoryEditorUserId, PVA.HistoryDate, PVA.CurrentHistoryText, PVA.PreviousHistoryText,
    PDA.LinkedPostsCount, PDA.DuplicateOfPostsCount, PDA.AvgLinkAgeDays, CM.TotalComments, CM.TotalCommentScore,
    CM.UniqueCommenters, UER.UpVotes, UER.DownVotes, UER.HighImpactQuestionsPostFirstYear, UER.CreationDate
HAVING
    COUNT(DISTINCT PDA.PostId) >= 1
    AND SUM(CM.UniqueCommenters) > 2

UNION ALL

SELECT
    UER.DisplayName AS OwnerUserName,
    UER.Reputation,
    UER.ReputationDecile,
    UER.GoldBadgesCount,
    PDA.PostId,
    PDA.Title AS PostTitle,
    PDA.PostCreationDate,
    PDA.PostScore,
    PDA.ViewCount,
    PDA.FavoriteCount,
    PDA.EffectiveClosedDate,
    PDA.TagName,
    T.Count AS TagPopularity,
    NULL AS LastEditorId,
    NULL AS LastEditHistoryDate,
    0 AS BodyTextChangeLength,
    PDA.LinkedPostsCount,
    NULL AS DuplicateOfPostsCount,
    0.0 AS AverageRelatedLinkAgeDays,
    CM.TotalComments,
    CM.TotalCommentScore,
    CM.UniqueCommenters,
    NULLIF(UER.UpVotes, 0) / NULLIF(UER.DownVotes, 1) AS OwnerUpDownVoteRatio,
    PERCENT_RANK() OVER (PARTITION BY UER.ReputationDecile ORDER BY PDA.PostScore DESC, PDA.PostCreationDate ASC) AS PostScoreRankInDecile,
    (
        SELECT COUNT(V.Id)
        FROM Votes AS V
        WHERE V.PostId = PDA.PostId
          AND V.VoteTypeId = 2
          AND V.CreationDate BETWEEN PDA.PostCreationDate AND PDA.PostCreationDate + INTERVAL '3 day'
    ) AS UpvotesInFirstThreeDays
FROM PostDetailWithTagsAndLinks AS PDA
INNER JOIN UserEngagementRanked AS UER ON PDA.OwnerUserId = UER.UserId
INNER JOIN Posts AS ParentQ ON PDA.AcceptedAnswerId = ParentQ.Id OR PDA.ParentId = ParentQ.Id
LEFT JOIN Tags AS T ON PDA.TagName = T.TagName
LEFT JOIN CommentMetrics AS CM ON PDA.PostId = CM.PostId
WHERE PDA.PostTypeId = 2
  AND UER.ReputationDecile > 6
  AND PDA.PostScore > 20
  AND ParentQ.Score > 100
  AND PDA.PostCreationDate > CAST('2024-10-01' AS date) - INTERVAL '4 year'
  AND PDA.TagName IS NOT NULL
  AND CM.TotalComments > 2
GROUP BY
    UER.DisplayName, UER.Reputation, UER.ReputationDecile, UER.GoldBadgesCount, PDA.PostId, PDA.Title, PDA.PostCreationDate,
    PDA.PostScore, PDA.ViewCount, PDA.FavoriteCount, PDA.EffectiveClosedDate, PDA.TagName, T.Count,
    PDA.LinkedPostsCount, CM.TotalComments, CM.TotalCommentScore, CM.UniqueCommenters, UER.UpVotes, UER.DownVotes,
    UER.HighImpactQuestionsPostFirstYear
HAVING
    (
        SELECT COUNT(V.Id)
        FROM Votes AS V
        WHERE V.PostId = PDA.PostId
          AND V.VoteTypeId = 2
          AND V.CreationDate BETWEEN PDA.PostCreationDate AND PDA.PostCreationDate + INTERVAL '3 day'
    ) > 7
ORDER BY
    OwnerUserName ASC, PostCreationDate DESC, PostScore DESC
LIMIT 2000;