-- {"query": "1012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2416}
WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) AS AvgPostScore,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        AVG(C.Score) AS AvgCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - U.LastAccessDate) AS DaysSinceLastAccess,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadgesCount,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadgesCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.CreationDate, U.LastAccessDate, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        (CASE WHEN P.Tags IS NOT NULL THEN array_length(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'), 1) ELSE NULL END) AS TagCount,
        COUNT(DISTINCT V_Up.Id) AS UpvoteCount,
        COUNT(DISTINCT V_Down.Id) AS DownvoteCount,
        COUNT(DISTINCT PH.Id) AS HistoryEntryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN 1 ELSE 0 END) AS ModerationActionCount,
        P.Tags AS RawTags
    FROM Posts P
    LEFT JOIN Votes V_Up ON P.Id = V_Up.PostId AND V_Up.VoteTypeId = 2
    LEFT JOIN Votes V_Down ON P.Id = V_Down.PostId AND V_Down.VoteTypeId = 3
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.Title, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastActivityDate, P.LastEditDate, P.ClosedDate, P.Tags
),
FilteredHighValuePosts AS (
    SELECT
        PQM.PostId,
        PQM.PostTypeId,
        PQM.Title,
        PQM.PostScore,
        PQM.ViewCount,
        UEM.Reputation AS OwnerReputation,
        'HighViewQuestion' AS ValueCategory,
        PQM.PostCreationDate,
        PQM.OwnerUserId
    FROM PostQualityMetrics PQM
    JOIN UserEngagementMetrics UEM ON PQM.OwnerUserId = UEM.UserId
    WHERE PQM.PostTypeId = 1
      AND PQM.ViewCount > 10000
      AND PQM.PostScore > 50
      AND UEM.Reputation > 5000
      AND PQM.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year'

    UNION ALL

    SELECT
        PQM.PostId,
        PQM.PostTypeId,
        PQM.Title,
        PQM.PostScore,
        PQM.ViewCount,
        UEM.Reputation AS OwnerReputation,
        'HighScoreAnswer' AS ValueCategory,
        PQM.PostCreationDate,
        PQM.OwnerUserId
    FROM PostQualityMetrics PQM
    JOIN UserEngagementMetrics UEM ON PQM.OwnerUserId = UEM.UserId
    WHERE PQM.PostTypeId = 2
      AND PQM.PostScore > 100
      AND UEM.Reputation BETWEEN 1000 AND 10000
      AND UEM.DaysSinceLastAccess < 90
      AND PQM.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
PostHistoryEventSequence AS (
    SELECT
        PH.PostId,
        PH.Id AS HistoryId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryCreationDate,
        LAG(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryTypeId,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryDate,
        LEAD(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextHistoryTypeId,
        LEAD(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextHistoryDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,19,20,35,36)
)
SELECT
    UEM.UserId,
    UEM.DisplayName,
    UEM.Reputation,
    UEM.TotalPosts,
    UEM.TotalQuestions,
    UEM.TotalAnswers,
    FHP.PostId,
    FHP.PostTypeId,
    FHP.Title,
    FHP.PostScore,
    FHP.ViewCount,
    FHP.ValueCategory,
    PQM.UpvoteCount,
    PQM.DownvoteCount,
    PQM.EditCount,
    PQM.ModerationActionCount,
    COALESCE(UEM.DisplayName, 'Deleted User') AS UserDisplayOrDefault,
    CASE
        WHEN FHP.PostTypeId = 1 AND PQM.ClosedDate IS NOT NULL THEN 'Closed Question'
        WHEN FHP.PostTypeId = 1 AND PQM.AnswerCount = 0 THEN 'Unanswered Question'
        WHEN FHP.PostTypeId = 2 AND FHP.PostScore > 50 THEN 'High-Quality Answer'
        ELSE 'Other Post Type'
    END AS PostCategoryDescription,
    NULLIF(split_part(substring(PQM.RawTags, 2, length(PQM.RawTags)-2), '><', 1), '') AS FirstTag,
    ROUND(CAST(PQM.UpvoteCount AS NUMERIC) / NULLIF(PQM.DownvoteCount, 0), 2) AS UpvoteDownvoteRatio,
    (SELECT
        STRING_AGG(CAST(P_Hist.PrevHistoryTypeId AS VARCHAR) || '->' || CAST(P_Hist.PostHistoryTypeId AS VARCHAR) || ' (' || DATE_PART('hour', P_Hist.HistoryCreationDate - P_Hist.PrevHistoryDate) || 'h)', ', ' ORDER BY P_Hist.HistoryCreationDate)
     FROM PostHistoryEventSequence P_Hist
     WHERE P_Hist.PostId = FHP.PostId AND P_Hist.PrevHistoryTypeId IS NOT NULL
     GROUP BY P_Hist.PostId
    ) AS PostHistoryFlow,
    RANK() OVER (PARTITION BY UEM.UserId, FHP.PostTypeId ORDER BY FHP.PostScore DESC, FHP.ViewCount DESC) AS PostScoreRankByUser,
    AVG(FHP.PostScore) OVER (
        PARTITION BY UEM.UserId
        ORDER BY PQM.PostCreationDate
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS AvgPostScoreLastYear,
    (SELECT EXISTS (
        SELECT 1
        FROM Posts P_Accepted
        WHERE P_Accepted.AcceptedAnswerId = FHP.PostId
          AND P_Accepted.OwnerUserId IS NOT DISTINCT FROM UEM.UserId
          AND P_Accepted.OwnerUserId <> FHP.OwnerReputation
    )) AS IsAcceptedAnswerOnDifferentUserQuestion,
    COALESCE(LP.TagName, 'NoMajorTag') AS MostFrequentTagForUser,
    LP.TagUseCount AS MostFrequentTagCount
FROM
    UserEngagementMetrics UEM
JOIN
    FilteredHighValuePosts FHP ON UEM.UserId = FHP.OwnerUserId
JOIN
    PostQualityMetrics PQM ON FHP.PostId = PQM.PostId
LEFT JOIN LATERAL (
    SELECT T.TagName, COUNT(P_Inner.Id) AS TagUseCount
    FROM Tags T
    JOIN Posts P_Inner ON P_Inner.Tags LIKE '%' || T.TagName || '%' AND P_Inner.OwnerUserId = UEM.UserId
    GROUP BY T.TagName
    ORDER BY COUNT(P_Inner.Id) DESC, T.TagName ASC
    LIMIT 1
) LP ON TRUE
WHERE
    UEM.TotalPosts > 10
    AND UEM.GoldBadgesCount > 0
    AND PQM.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year'
    AND PQM.TagCount IS NOT NULL AND PQM.TagCount > 0
    AND (
        (PQM.LastEditDate IS NOT NULL AND PQM.LastEditDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 month')
        OR PQM.CommentCount > 5
    )
ORDER BY
    UEM.Reputation DESC,
    UEM.DaysSinceLastAccess ASC,
    FHP.PostScore DESC,
    FHP.ViewCount DESC
LIMIT 10000;