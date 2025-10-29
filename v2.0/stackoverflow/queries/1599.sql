-- {"query": "1599.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2032}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgRelevantPostScore,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCount,
        MAX(P.CreationDate) AS LatestPostDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.UserId = U.Id) AS TotalCommentsMade,
        (SELECT AVG(C.Score) FROM Comments C WHERE C.UserId = U.Id AND C.Score IS NOT NULL) AS AvgCommentScoreMade,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS TotalPostsEditedBySelf
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(P.Id) > 5
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        P.Tags,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate ASC) AS RankByScoreForOwner,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastEditDate ASC) AS PrevEditDate,
        (
            SELECT COUNT(DISTINCT PH_INNER.UserId)
            FROM PostHistory PH_INNER
            WHERE PH_INNER.PostId = P.Id
              AND PH_INNER.PostHistoryTypeId IN (4, 5, 6)
        ) AS UniqueEditorsCount,
        (
            SELECT AVG(C_INNER.Score)
            FROM Comments C_INNER
            WHERE C_INNER.PostId = P.Id AND C_INNER.Score IS NOT NULL
        ) AS AvgPostCommentScore,
        (
            SELECT MAX(C_INNER.CreationDate)
            FROM Comments C_INNER
            WHERE C_INNER.PostId = P.Id
        ) AS LatestCommentDate
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= DATE '2020-01-01'
      AND P.OwnerUserId IS NOT NULL
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS EditSequence,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS PreviousEditDate,
        COALESCE(EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC))) / 3600, 0) AS HoursSincePreviousEdit,
        CASE
            WHEN PH.PostHistoryTypeId IN (10, 11) THEN 'Close/Reopen Event'
            WHEN PH.PostHistoryTypeId IN (12, 13) THEN 'Delete/Undelete Event'
            WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 'Content Edit Event'
            ELSE 'Other Event'
        END AS HistoryEventType,
        CR.Name AS CloseReason
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND CR.Id = CAST(PH.Comment AS INTEGER)
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
),
TagPerformance AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName,
        P.OwnerUserId
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags <> '' AND P.Tags LIKE '%>%'
),
AggregatedTagStats AS (
    SELECT
        TP.TagName,
        COUNT(DISTINCT TP.PostId) AS TotalTaggedPosts,
        AVG(PM.PostScore) AS AvgScoreForTag,
        SUM(COALESCE(PM.ViewCount, 0)) AS TotalViewCountForTag,
        COUNT(DISTINCT PM.OwnerUserId) AS UniqueAuthorsForTag,
        RANK() OVER (ORDER BY COUNT(DISTINCT TP.PostId) DESC, SUM(COALESCE(PM.ViewCount,0)) DESC) AS TagPopularityRank
    FROM TagPerformance TP
    JOIN PostHistoricalMetrics PM ON TP.PostId = PM.PostId
    GROUP BY TP.TagName
    HAVING COUNT(DISTINCT TP.PostId) > 100
),
UserTopTagSelection AS (
    SELECT
        TP.OwnerUserId AS UserId,
        TP.TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER(PARTITION BY TP.OwnerUserId ORDER BY COUNT(*) DESC, TP.TagName ASC) as rn
    FROM TagPerformance TP
    WHERE TP.OwnerUserId IS NOT NULL
    GROUP BY TP.OwnerUserId, TP.TagName
),
-- Summarize post history event counts per post
PostHistorySummary AS (
    SELECT
        PEA.PostId,
        SUM(CASE WHEN PEA.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS TotalContentEdits,
        SUM(CASE WHEN PEA.PostHistoryTypeId IN (10,11) THEN 1 ELSE 0 END) AS TotalCloseReopenEvents,
        SUM(CASE WHEN PEA.PostHistoryTypeId IN (12,13) THEN 1 ELSE 0 END) AS TotalDeleteUndeleteEvents,
        AVG(PEA.HoursSincePreviousEdit) AS AvgHoursBetweenEdits,
        MAX(PEA.EditDate) AS LastEditDate
    FROM PostEditActivity PEA
    GROUP BY PEA.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostsEditedBySelf,
    PM.PostId,
    PM.PostCreationDate,
    PM.PostScore,
    PM.ViewCount,
    PM.AnswerCount,
    PM.UniqueEditorsCount,
    PM.AvgPostCommentScore,
    PM.RankByScoreForOwner,
    ATS.TagName AS TopContributingTag,
    ATS.AvgScoreForTag AS TopTagAvgScore,
    ATS.TagPopularityRank AS TopTagRank,
    PHS.TotalContentEdits,
    PHS.TotalCloseReopenEvents,
    COALESCE(ROUND(EXTRACT(EPOCH FROM (PM.LastEditDate - PM.PostCreationDate)) / 3600.0, 2), 0) AS HoursToFirstEdit,
    COALESCE(PHS.AvgHoursBetweenEdits, 0) AS AvgHoursBetweenEdits,
    COALESCE(PM.LatestCommentDate, PM.LastActivityDate, PM.LastEditDate, PM.PostCreationDate) AS MostRecentActivity,
    UTS.TagName AS UserTopTag,
    UTS.TagCount AS UserTopTagCount
FROM UserActivitySummary UAS
JOIN PostHistoricalMetrics PM ON UAS.UserId = PM.OwnerUserId
LEFT JOIN AggregatedTagStats ATS ON ATS.TagName = (
    SELECT TagName
    FROM UserTopTagSelection UT
    WHERE UT.UserId = UAS.UserId AND UT.rn = 1
    LIMIT 1
)
LEFT JOIN UserTopTagSelection UTS ON UTS.UserId = UAS.UserId AND UTS.rn = 1
LEFT JOIN PostHistorySummary PHS ON PHS.PostId = PM.PostId
WHERE PM.PostId IS NOT NULL
ORDER BY UAS.UserId, PM.PostCreationDate;