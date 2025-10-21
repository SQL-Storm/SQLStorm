WITH UserDemographics AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'GhostUser') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserRegistrationDate,
        U.LastAccessDate,
        U.Views AS ProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        (EXTRACT(YEAR FROM CAST('2024-10-01 12:34:56' AS TIMESTAMP) ) - EXTRACT(YEAR FROM U.CreationDate)) AS YearsOnPlatform,
        -- Correlated subquery: Count of questions asked by the user
        (SELECT COUNT(P_Q.Id) FROM Posts P_Q WHERE P_Q.OwnerUserId = U.Id AND P_Q.PostTypeId = 1) AS QuestionsCount,
        -- Correlated subquery: Count of answers provided by the user
        (SELECT COUNT(P_A.Id) FROM Posts P_A WHERE P_A.OwnerUserId = U.Id AND P_A.PostTypeId = 2) AS AnswersCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostComplexMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        COALESCE(P.Score, 0) AS PostScore,
        COALESCE(P.ViewCount, 0) AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.Title,
        P.Body,
        P.Tags,
        -- Post age in days
        NULLIF(DATE_PART('day', CAST('2024-10-01 12:34:56' AS TIMESTAMP) - P.CreationDate), 0) AS PostAgeDays,
        -- ActivityScore
        (COALESCE(P.ViewCount, 0) * 0.1) + (COALESCE(P.AnswerCount, 0) * 0.5) - (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - P.LastActivityDate)) / 86400 * 0.01) AS ActivityScore,
        -- Aggregated PostHistory data: total edits, close events, reopen events
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEvents,
        -- Latest close reason ID as string
        (SELECT NULLIF(SUBSTRING(PH_latest.Comment, 1, 3), '') 
         FROM PostHistory PH_latest 
         WHERE PH_latest.PostId = P.Id AND PH_latest.PostHistoryTypeId = 10 
         ORDER BY PH_latest.CreationDate DESC LIMIT 1) AS LastCloseReasonIdString,
        -- Average score of comments on this post
        COALESCE(AVG(C.Score) FILTER (WHERE C.Score IS NOT NULL), 0.0) AS AvgCommentScore,
        -- Has duplicate link
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS HasDuplicateLink,
        -- Window function: rank within post type
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY COALESCE(P.Score, 0) + COALESCE(AVG(C.Score) FILTER (WHERE C.Score IS NOT NULL), 0) DESC NULLS LAST) AS PostTypeCombinedRank,
        -- Score difference from previous by owner
        COALESCE(P.Score, 0) - COALESCE(LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate), 0) AS ScoreChangeFromPrevious,
        -- Tag count
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'), 1) AS TagCount,
        -- Recent active vote count
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId IN (2,3) AND V.CreationDate > P.LastActivityDate - INTERVAL '1 month') AS RecentActiveVoteCount
    FROM Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.Tags IS NOT NULL AND P.Tags LIKE '<%>%' -- Filter for posts with tags
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount,
             P.CreationDate, P.LastActivityDate, P.ClosedDate, P.CommunityOwnedDate, P.Title, P.Body, P.Tags
),
HighlyVotedComments AS (
    SELECT
        C.PostId,
        COUNT(DISTINCT C.UserId) AS UniqueCommentersWithHighScore,
        SUM(CASE WHEN C.Score > 5 THEN 1 ELSE 0 END) AS HighScoreCommentsCount
    FROM Comments C
    WHERE C.Score > 2 AND C.UserId IS NOT NULL
    GROUP BY C.PostId
    HAVING COUNT(DISTINCT C.UserId) > 1
),
TopQuestionContributors AS (
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS QuestionCount,
        SUM(P.ViewCount) AS TotalQuestionViews
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.PostTypeId = 1 AND P.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY U.Id
    ORDER BY TotalQuestionViews DESC
    LIMIT 500
),
ModeratorActivitySummary AS (
    SELECT
        U.Id AS UserId,
        COUNT(PH.Id) AS ModeratorHistoryActions,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModerationSpecificActions,
        AVG(EXTRACT(EPOCH FROM (PH.CreationDate - U.CreationDate)) / 86400) AS AvgTimeToAction
    FROM Users U
    JOIN PostHistory PH ON U.Id = PH.UserId
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY U.Id
    HAVING COUNT(PH.Id) > 5
)
SELECT
    UD.UserId,
    UD.DisplayName,
    UD.Reputation,
    UD.YearsOnPlatform,
    PCM.PostId,
    PCM.PostTypeName,
    'HighReputationQuestionAnalysis' AS AnalysisType,
    PCM.PostScore,
    PCM.PostViewCount,
    PCM.PostAnswerCount,
    PCM.TotalEdits,
    CRT.Name AS LastCloseReasonName,
    PCM.HasDuplicateLink,
    PCM.ActivityScore,
    UD.QuestionsCount AS PostEngagementCount,
    UD.GoldBadges AS RelevantBadges,
    PCM.PostTypeCombinedRank,
    COALESCE(MAS.ModerationSpecificActions, 0) AS OwnerModerationActions,
    CASE
        WHEN PCM.ClosedDate IS NOT NULL AND PCM.PostScore < 0 THEN 'Closed & Negative'
        WHEN PCM.HasDuplicateLink = 1 AND PCM.PostAnswerCount = 0 THEN 'Duplicate & Unanswered'
        WHEN PCM.ActivityScore > 100 AND PCM.PostAnswerCount > 5 THEN 'Highly Engaged & Solved'
        WHEN PCM.AvgCommentScore > 3 AND HVC.HighScoreCommentsCount > 0 THEN 'Active Discussion'
        WHEN PCM.PostAgeDays > 365 AND PCM.PostViewCount < 100 THEN 'Stale Post'
        ELSE 'General Activity'
    END AS PostHealthStatus,
    CAST(PCM.PostFavoriteCount AS NUMERIC) / NULLIF(PCM.PostViewCount, 0) AS FavoriteRatio,
    CASE
        WHEN PCM.Tags LIKE '%<sql>%' OR PCM.Tags LIKE '%<database>%'
            THEN 'SQL/DB-Related'
        WHEN PCM.Tags LIKE '%<python>%' OR PCM.Tags LIKE '%<java>%'
            THEN 'Programming-Related'
        ELSE 'Other Tags'
    END AS TagCategory,
    CASE
        WHEN LOWER(PCM.Body) LIKE '%solution%' THEN 'Mentions Solution'
        WHEN LOWER(PCM.Body) LIKE '%error message%' THEN 'Has Error Message'
        ELSE 'No Specific Body Keyword'
    END AS BodyContentHint,
    CASE WHEN UD.UserId IN (SELECT TQC.UserId FROM TopQuestionContributors TQC) THEN TRUE ELSE FALSE END AS IsTopQuestionContributor,
    NTILE(4) OVER (ORDER BY UD.Reputation DESC) AS ReputationQuartile,
    AVG(PCM.PostScore) OVER (PARTITION BY UD.UserId ORDER BY PCM.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore
FROM PostComplexMetrics PCM
LEFT JOIN UserDemographics UD ON PCM.OwnerUserId = UD.UserId
LEFT JOIN CloseReasonTypes CRT ON CAST(PCM.LastCloseReasonIdString AS BIGINT) = CRT.Id
LEFT JOIN HighlyVotedComments HVC ON PCM.PostId = HVC.PostId
LEFT JOIN ModeratorActivitySummary MAS ON UD.UserId = MAS.UserId
WHERE
    UD.Reputation > 10000
    AND PCM.PostTypeId = 1
    AND PCM.PostAgeDays < 365
    AND PCM.TotalEdits > 0
    AND EXISTS (
        SELECT 1
        FROM Comments C_inner
        WHERE C_inner.PostId = PCM.PostId AND C_inner.CreationDate BETWEEN PCM.PostCreationDate AND PCM.PostCreationDate + INTERVAL '1 month'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks PL_inner
        WHERE PL_inner.RelatedPostId = PCM.PostId AND PL_inner.LinkTypeId = 3
    )

UNION ALL

SELECT
    UD.UserId,
    UD.DisplayName,
    UD.Reputation,
    UD.YearsOnPlatform,
    PCM.PostId,
    PCM.PostTypeName,
    'MidReputationAnswerAnalysis' AS AnalysisType,
    PCM.PostScore,
    PCM.PostViewCount,
    PCM.PostAnswerCount,
    PCM.TotalEdits,
    CRT.Name AS LastCloseReasonName,
    PCM.HasDuplicateLink,
    PCM.ActivityScore,
    UD.AnswersCount AS PostEngagementCount,
    UD.SilverBadges AS RelevantBadges,
    PCM.PostTypeCombinedRank,
    COALESCE(MAS.ModerationSpecificActions, 0) AS OwnerModerationActions,
    CASE
        WHEN PCM.ClosedDate IS NOT NULL AND PCM.PostScore < 0 THEN 'Closed & Negative'
        WHEN PCM.HasDuplicateLink = 1 AND PCM.PostAnswerCount = 0 THEN 'Duplicate & Unanswered'
        WHEN PCM.ActivityScore > 100 AND PCM.PostAnswerCount > 5 THEN 'Highly Engaged & Solved'
        WHEN PCM.AvgCommentScore > 3 AND HVC.HighScoreCommentsCount > 0 THEN 'Active Discussion'
        WHEN PCM.PostAgeDays > 365 AND PCM.PostViewCount < 100 THEN 'Stale Post'
        ELSE 'General Activity'
    END AS PostHealthStatus,
    CAST(PCM.PostFavoriteCount AS NUMERIC) / NULLIF(PCM.PostViewCount, 0) AS FavoriteRatio,
    CASE
        WHEN PCM.Tags LIKE '%<sql>%' OR PCM.Tags LIKE '%<database>%'
            THEN 'SQL/DB-Related'
        WHEN PCM.Tags LIKE '%<python>%' OR PCM.Tags LIKE '%<java>%'
            THEN 'Programming-Related'
        ELSE 'Other Tags'
    END AS TagCategory,
    CASE
        WHEN LOWER(PCM.Body) LIKE '%solution%' THEN 'Mentions Solution'
        WHEN LOWER(PCM.Body) LIKE '%error message%' THEN 'Has Error Message'
        ELSE 'No Specific Body Keyword'
    END AS BodyContentHint,
    CASE WHEN UD.UserId IN (SELECT TQC.UserId FROM TopQuestionContributors TQC) THEN TRUE ELSE FALSE END AS IsTopQuestionContributor,
    NTILE(4) OVER (ORDER BY UD.Reputation DESC) AS ReputationQuartile,
    AVG(PCM.PostScore) OVER (PARTITION BY UD.UserId ORDER BY PCM.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore
FROM PostComplexMetrics PCM
LEFT JOIN UserDemographics UD ON PCM.OwnerUserId = UD.UserId
LEFT JOIN CloseReasonTypes CRT ON CAST(PCM.LastCloseReasonIdString AS BIGINT) = CRT.Id
LEFT JOIN HighlyVotedComments HVC ON PCM.PostId = HVC.PostId
LEFT JOIN ModeratorActivitySummary MAS ON UD.UserId = MAS.UserId
WHERE
    UD.Reputation BETWEEN 1000 AND 10000
    AND PCM.PostTypeId = 2
    AND PCM.PostAgeDays BETWEEN 30 AND 730
    AND PCM.PostScore >= 5
    AND PCM.RecentActiveVoteCount > 1
    AND (LOWER(PCM.Body) LIKE '%code%' OR LOWER(PCM.Body) LIKE '%example%')
ORDER BY
    Reputation DESC,
    ActivityScore DESC,
    PostTypeCombinedRank ASC
LIMIT 20000;