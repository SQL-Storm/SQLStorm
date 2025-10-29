-- {"query": "1462.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2987} 

WITH UserStats AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.DisplayName,
        U.Location,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsGenerated,
        MAX(P.CreationDate) AS LastPostCreationDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        MAX(CASE WHEN LOWER(B.Name) LIKE '%editor%' THEN 1 ELSE 0 END) AS HasEditorBadge
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON P.Id = V.PostId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.Location,
        U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        P.ClosedDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        (CAST(COALESCE(P.Score, 0) AS DECIMAL) / NULLIF(P.ViewCount, 0)) AS ScoreToViewRatio,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY COALESCE(P.Score, 0) DESC, COALESCE(P.ViewCount, 0) DESC) AS RankByScoreAndViewsByUser,
        AVG(COALESCE(P.Score, 0)) OVER (PARTITION BY P.OwnerUserId) AS AvgScoreByUser,
        AVG(COALESCE(P.ViewCount, 0)) OVER (PARTITION BY P.OwnerUserId) AS AvgViewsByUser,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostDate,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'HasAcceptedAnswer'
            WHEN P.ClosedDate IS NOT NULL THEN 'ClosedQuestion'
            WHEN P.ParentId IS NOT NULL AND P.AcceptedAnswerId IS NULL AND COALESCE(P.Score, 0) < 0 THEN 'LowQualityAnswer'
            ELSE 'NormalPost'
        END AS PostStatusCategory,
        (SELECT MAX(V_Inner.CreationDate) FROM Votes AS V_Inner WHERE V_Inner.PostId = P.Id AND V_Inner.VoteTypeId = 1) AS AcceptedAnswerSetDate
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2)
),
PostHistoryEvents AS (
    SELECT
        PH.Id AS HistoryId,
        PH.PostId,
        PH.UserId AS HistoryUserId,
        PH.CreationDate AS HistoryDate,
        PHT.Name AS HistoryTypeName,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryText,
        PH.PostHistoryTypeId
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (
        4, 5, 6, -- Edits (Title, Body, Tags)
        10, -- Post Closed
        11, -- Post Reopened
        12, -- Post Deleted
        13, -- Post Undeleted
        14, -- Post Locked
        15, -- Post Unlocked
        35, -- Post Migrated Away
        36  -- Post Migrated Here
    )
),
PostModerationSummary AS (
    SELECT
        PostId,
        COUNT(DISTINCT HistoryId) AS TotalHistoryEvents,
        COUNT(DISTINCT HistoryUserId) AS DistinctEditors,
        MAX(HistoryDate) AS LastModerationActionDate,
        SUM(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteCount,
        MAX(CASE WHEN PostHistoryTypeId = 10 THEN HistoryComment END) AS LatestCloseReasonComment,
        MAX(CASE WHEN PostHistoryTypeId = 35 THEN 'TRUE' ELSE 'FALSE' END) AS WasMigratedAway
    FROM PostHistoryEvents
    GROUP BY PostId
),
PostTagsFlattened AS (
    SELECT
        P.Id AS PostId,
        TRIM(tag_val) AS TagName
    FROM Posts AS P
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag_val
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
TagUsageSummary AS (
    SELECT
        PTF.PostId,
        STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName) AS TagsList,
        COUNT(DISTINCT T.Id) AS NumberOfTags,
        SUM(COALESCE(T.Count, 0)) AS TotalTagPopularityScore,
        MAX(CASE WHEN T.IsModeratorOnly THEN 1 ELSE 0 END) AS HasModeratorOnlyTag,
        MAX(CASE WHEN LOWER(T.TagName) = 'sql' THEN 1 ELSE 0 END) AS HasSQLTag
    FROM PostTagsFlattened AS PTF
    JOIN Tags AS T ON PTF.TagName = T.TagName
    GROUP BY PTF.PostId
)
SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.Location,
    US.TotalPosts,
    US.TotalQuestions,
    US.TotalAnswers,
    US.TotalComments,
    US.TotalPostScoreReceived,
    US.TotalPostViewsGenerated,
    US.UserProfileViews,
    US.UserUpVotesGiven,
    US.UserDownVotesGiven,
    US.HasGoldBadge,
    US.HasEditorBadge,
    PDM.PostId,
    PDM.PostTypeId,
    PDM.PostCreationDate,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.AnswerCount,
    PDM.FavoriteCount,
    COALESCE(PDM.ScoreToViewRatio, 0) AS ScoreToViewRatio,
    PDM.PostStatusCategory,
    PDM.AcceptedAnswerSetDate,
    PDM.RankByScoreAndViewsByUser,
    COALESCE(PDM.AvgScoreByUser, 0) AS AvgScoreByUser,
    COALESCE(PDM.AvgViewsByUser, 0) AS AvgViewsByUser,
    COALESCE(EXTRACT(EPOCH FROM (PDM.PostCreationDate - PDM.PreviousPostDate)) / 3600.0, 0) AS HoursSincePreviousPost,
    COALESCE(PMS.TotalHistoryEvents, 0) AS TotalHistoryEvents,
    COALESCE(PMS.DistinctEditors, 0) AS DistinctEditors,
    COALESCE(PMS.EditCount, 0) AS EditCount,
    COALESCE(PMS.CloseCount, 0) AS CloseCount,
    COALESCE(PMS.DeleteCount, 0) AS DeleteCount,
    PMS.LatestCloseReasonComment,
    COALESCE(PMS.WasMigratedAway, 'FALSE') AS WasMigratedAway,
    TUS.TagsList,
    COALESCE(TUS.NumberOfTags, 0) AS NumberOfTags,
    COALESCE(TUS.TotalTagPopularityScore, 0) AS TotalTagPopularityScore,
    COALESCE(TUS.HasModeratorOnlyTag, 0) AS HasModeratorOnlyTag,
    COALESCE(TUS.HasSQLTag, 0) AS HasSQLTag,
    (CASE
        WHEN COALESCE(PDM.PostScore, 0) >= 100 AND COALESCE(PDM.ViewCount, 0) >= 10000 AND COALESCE(PDM.AnswerCount, 0) >= 5 THEN 'HighImpact'
        WHEN COALESCE(PDM.PostScore, 0) >= 20 AND COALESCE(PDM.ViewCount, 0) >= 1000 AND COALESCE(PDM.AnswerCount, 0) >= 1 THEN 'MediumImpact'
        ELSE 'LowImpact'
    END) AS ImpactCategory,
    COALESCE(PDM.ScoreToViewRatio, 0) * (1 + (CASE WHEN PDM.AcceptedAnswerId IS NOT NULL THEN 0.5 ELSE 0 END)) AS AdjustedQualityScore,
    CASE
        WHEN PDM.ClosedDate IS NOT NULL AND COALESCE(PMS.CloseCount, 0) > 0 THEN 'ClosedAndModerated'
        WHEN PDM.PostStatusCategory = 'LowQualityAnswer' AND COALESCE(PDM.PostScore, 0) < COALESCE(PDM.AvgScoreByUser, 0) * 0.5 THEN 'SubstandardPost'
        WHEN US.Reputation > 10000 AND COALESCE(PMS.EditCount, 0) > 5 AND COALESCE(PDM.ScoreToViewRatio, 0) < 0.01 THEN 'HighReputationLowQualityPost'
        ELSE 'Normal'
    END AS PostAssessment,
    (SELECT COUNT(C_sub.Id) FROM Comments C_sub WHERE C_sub.PostId = PDM.PostId AND C_sub.CreationDate > PDM.PostCreationDate + INTERVAL '1 hour') AS CommentsAfterFirstHour,
    (SELECT AVG(P_other.Score) FROM Posts P_other WHERE P_other.OwnerUserId = US.UserId AND P_other.Id != PDM.PostId AND P_other.PostTypeId = PDM.PostTypeId) AS AvgScoreOfSimilarPostsByUser,
    NULLIF(COALESCE(US.TotalUpvotesReceivedOnPosts, 0) + COALESCE(US.TotalDownvotesReceivedOnPosts, 0), 0) AS TotalVotesReceivedOnPosts,
    CAST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - US.UserCreationDate)) / (3600 * 24 * 365.25) AS DECIMAL(10,2)) AS UserTenureYears
FROM UserStats AS US
LEFT JOIN PostDetailedMetrics AS PDM ON US.UserId = PDM.OwnerUserId
LEFT JOIN PostModerationSummary AS PMS ON PDM.PostId = PMS.PostId
LEFT JOIN TagUsageSummary AS TUS ON PDM.PostId = TUS.PostId
WHERE
    US.Reputation >= 1000
    AND US.TotalPosts > 5
    AND PDM.PostId IS NOT NULL
    AND PDM.PostCreationDate >= '2020-01-01'
    AND (
        (COALESCE(PDM.ScoreToViewRatio, 0) > 0.01 AND COALESCE(PDM.PostScore, 0) > 5)
        OR PDM.AcceptedAnswerId IS NOT NULL
        OR COALESCE(PMS.CloseCount, 0) > 0
        OR COALESCE(TUS.HasSQLTag, 0) = 1
        OR US.UserProfileViews > 1000
    )
ORDER BY
    US.Reputation DESC,
    AdjustedQualityScore DESC,
    UserTenureYears DESC,
    PDM.PostCreationDate DESC
LIMIT 10000;
