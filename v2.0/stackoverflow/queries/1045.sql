-- {"query": "1045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2543}
WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(P.Score, 0)) FILTER (WHERE P.Id IS NOT NULL) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        (U.UpVotes + U.DownVotes) AS TotalVotesCast,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MIN(P.CreationDate) AS FirstPostDate,
        U.Views AS UserProfileViews
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
PostEditAndClosureInfo AS (
    SELECT
        P.Id AS PostId,
        P.Title AS PostTitle,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL THEN CRT.Name ELSE NULL END) AS LatestCloseReason,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL) AS UniqueEditors,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosureEventsCount,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS LatestEditHistoryDate,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS FirstEditHistoryDate,
        P.OwnerUserId
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN CloseReasonTypes CRT ON PH.Comment = CAST(CRT.Id AS TEXT) AND PH.PostHistoryTypeId = 10
    WHERE P.PostTypeId = 1
    GROUP BY
        P.Id, P.Title, P.PostTypeId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.OwnerUserId
),
TagPopularityAndMetadata AS (
    SELECT
        tag_unnested.tag_name,
        COUNT(DISTINCT P.Id) AS PostsWithTag,
        SUM(COALESCE(P.Score, 0)) AS TotalScoreForTag,
        AVG(COALESCE(P.Score, 0)) AS AverageScoreForTag,
        MAX(P.CreationDate) AS LatestPostWithTag,
        MIN(P.CreationDate) AS EarliestPostWithTag,
        T.IsModeratorOnly,
        T.IsRequired,
        (SELECT COUNT(DISTINCT B.UserId) FROM Badges B WHERE B.Name = tag_unnested.tag_name AND B.TagBased = TRUE) AS UsersWithTagBadge
    FROM Posts P
    CROSS JOIN LATERAL (SELECT UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag_name) tag_unnested
    LEFT JOIN Tags T ON tag_unnested.tag_name = T.TagName
    WHERE P.Tags IS NOT NULL AND P.Tags <> ''
    GROUP BY
        tag_unnested.tag_name, T.IsModeratorOnly, T.IsRequired
),
PrimaryTagging AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS tag_name,
        ROW_NUMBER() OVER (PARTITION BY P.Id ORDER BY (SELECT 1)) as rn
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags <> '' AND P.PostTypeId = 1
),
UserClosedCounts AS (
    -- Precompute per-user number of closed questions (count of posts with ClosureEventsCount>0)
    SELECT
        PECI.OwnerUserId AS UserId,
        SUM(CASE WHEN PECI.ClosureEventsCount > 0 THEN 1 ELSE 0 END) AS NumClosedQuestions
    FROM PostEditAndClosureInfo PECI
    GROUP BY PECI.OwnerUserId
),
UserMaxTagAvg AS (
    -- Precompute per-user max average tag score across their question tags (join via primary tag)
    SELECT
        UAM.UserId,
        MAX(COALESCE(TPM.AverageScoreForTag, 0)) AS MaxAvgTagScore
    FROM UserActivityMetrics UAM
    LEFT JOIN PostEditAndClosureInfo PECI ON UAM.UserId = PECI.OwnerUserId
    LEFT JOIN PrimaryTagging PT ON PECI.PostId = PT.PostId AND PT.rn = 1
    LEFT JOIN TagPopularityAndMetadata TPM ON PT.tag_name = TPM.tag_name
    GROUP BY UAM.UserId
)
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    UAM.UserCreationDate,
    UAM.LastAccessDate,
    UAM.TotalPosts,
    UAM.QuestionsAsked,
    UAM.AnswersGiven,
    UAM.TotalPostScore,
    UAM.AvgPostScore,
    UAM.TotalCommentsMade,
    UAM.TotalCommentScore,
    UAM.TotalVotesCast,
    COALESCE(UAM.UserProfileViews, 0) AS UserProfileViews,
    PECI.PostId AS QuestionId,
    PECI.PostTitle AS QuestionTitle,
    PECI.PostCreationDate AS QuestionCreationDate,
    PECI.LastEditDate AS QuestionLastEditDate,
    PECI.ClosedDate AS QuestionClosedDate,
    PECI.EditCount AS QuestionEditCount,
    PECI.LatestCloseReason,
    PECI.UniqueEditors AS QuestionUniqueEditors,
    PECI.ClosureEventsCount AS QuestionClosureEventsCount,
    TPM.tag_name AS PrimaryTag,
    TPM.PostsWithTag,
    TPM.TotalScoreForTag,
    TPM.AverageScoreForTag,
    COALESCE(TPM.IsModeratorOnly, FALSE) AS TagIsModeratorOnly,
    COALESCE(TPM.IsRequired, FALSE) AS TagIsRequired,
    COALESCE(TPM.UsersWithTagBadge, 0) AS UsersWithTagBadge,
    AGE(UAM.LastAccessDate, UAM.UserCreationDate) AS UserAccountAge,
    EXTRACT(EPOCH FROM (UAM.LastAccessDate - UAM.UserCreationDate)) / 86400.0 AS DaysSinceCreation,
    CASE
        WHEN UAM.Reputation >= 100000 THEN 'Stack Overflow Legend'
        WHEN UAM.Reputation >= 50000 THEN 'Veteran Contributor'
        WHEN UAM.Reputation >= 10000 THEN 'Experienced Developer'
        WHEN UAM.Reputation >= 1000 THEN 'Active Community Member'
        WHEN UAM.Reputation >= 100 THEN 'Engaged User'
        ELSE 'Newbie'
    END AS ReputationTier,
    (UAM.TotalPosts * 0.7 + UAM.TotalCommentsMade * 0.3 + UAM.TotalPostScore * 0.5 + UAM.QuestionsAsked * 0.2 + UAM.AnswersGiven * 0.4 - UAM.TotalVotesCast * 0.1) AS UserEngagementScore,
    UPPER(LEFT(UAM.DisplayName, 3)) || LPAD(SUBSTRING(UAM.DisplayName FROM LENGTH(UAM.DisplayName)-2 FOR 3), 3, '*') AS DisplayNameHashPartial,
    (P_Body.Body ILIKE '%performance%' OR P_Body.Body ILIKE '%optimization%' OR P_Body.Body ILIKE '%speed%') AS ContainsPerformanceKeywords,
    COALESCE(P_Body.ContentLicense, 'Unknown License') AS PostContentLicense,
    RANK() OVER (PARTITION BY
        CASE
            WHEN UAM.Reputation >= 100000 THEN 'Stack Overflow Legend'
            WHEN UAM.Reputation >= 50000 THEN 'Veteran Contributor'
            WHEN UAM.Reputation >= 10000 THEN 'Experienced Developer'
            WHEN UAM.Reputation >= 1000 THEN 'Active Community Member'
            WHEN UAM.Reputation >= 100 THEN 'Engaged User'
            ELSE 'Newbie'
        END
        ORDER BY UAM.TotalPostScore DESC, UAM.LastAccessDate DESC
    ) AS RankWithinReputationTier,
    AVG(UAM.TotalPostScore) OVER (PARTITION BY
        CASE
            WHEN UAM.Reputation >= 100000 THEN 'Stack Overflow Legend'
            WHEN UAM.Reputation >= 50000 THEN 'Veteran Contributor'
            WHEN UAM.Reputation >= 10000 THEN 'Experienced Developer'
            WHEN UAM.Reputation >= 1000 THEN 'Active Community Member'
            WHEN UAM.Reputation >= 100 THEN 'Engaged User'
            ELSE 'Newbie'
        END
    ) AS AvgScoreForRepTier,
    LAG(UAM.QuestionsAsked, 1, 0) OVER (ORDER BY UAM.UserCreationDate, UAM.UserId) AS PreviousUserQuestionsCount,
    SUM(PECI.EditCount) OVER (PARTITION BY PECI.OwnerUserId ORDER BY PECI.PostCreationDate) AS RunningEditCountForUser,
    NTH_VALUE(PECI.LatestCloseReason, 1) OVER (PARTITION BY PECI.OwnerUserId ORDER BY PECI.PostCreationDate DESC, PECI.PostId DESC) AS LatestQuestionCloseReasonForUser,
    (PECI.ClosedDate IS NOT NULL AND PECI.ClosedDate > COALESCE(PECI.LastEditDate, PECI.PostCreationDate)) AS ClosedAfterLastEdit,
    ABS(EXTRACT(DAY FROM (COALESCE(PECI.LastEditDate, PECI.PostCreationDate) - PECI.PostCreationDate))) AS DaysFromCreationToLastEdit
FROM UserActivityMetrics UAM
LEFT JOIN PostEditAndClosureInfo PECI ON UAM.UserId = PECI.OwnerUserId
LEFT JOIN Posts P_Body ON PECI.PostId = P_Body.Id
LEFT JOIN PrimaryTagging PT ON PECI.PostId = PT.PostId AND PT.rn = 1
LEFT JOIN TagPopularityAndMetadata TPM ON PT.tag_name = TPM.tag_name
LEFT JOIN UserClosedCounts UCC ON UAM.UserId = UCC.UserId
LEFT JOIN UserMaxTagAvg UMA ON UAM.UserId = UMA.UserId
WHERE
    UAM.QuestionsAsked > 0
    AND UAM.Reputation > 500
    AND UAM.UserCreationDate >= DATE '2015-01-01'
    AND PECI.PostTitle IS NOT NULL
    AND PECI.PostTitle NOT ILIKE '%[duplicate]%'
    AND (PECI.EditCount > 2 OR PECI.LatestCloseReason IS NOT NULL)
    AND TPM.PostsWithTag > 500
    AND (P_Body.Body IS NOT NULL AND LENGTH(P_Body.Body) > 150)
    AND (UAM.DisplayName IS NOT NULL AND LENGTH(UAM.DisplayName) BETWEEN 4 AND 25)
    AND UAM.AvgPostScore > 7
    AND COALESCE(UCC.NumClosedQuestions, 0) < 3
    AND COALESCE(UMA.MaxAvgTagScore, 0) > 15
ORDER BY
    UserEngagementScore DESC, UAM.LastAccessDate DESC
LIMIT 1000;