-- {"query": "1480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2469} 
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COALESCE(AVG(P.Score) OVER (PARTITION BY U.Id), 0) AS AvgUserPostScore,
        MAX(U.LastAccessDate) AS LastAccess
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.CreationDate >= '2010-01-01' -- Focus on users active after a certain date
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ViewCount,
        P.Score AS PostScore,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Tags,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        AVG(CASE WHEN C.Score IS NOT NULL THEN C.Score ELSE 0 END) AS AvgCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        ARRAY_AGG(DISTINCT PH.PostHistoryTypeId) FILTER (WHERE PH.PostHistoryTypeId IS NOT NULL) AS AllHistoryTypes,
        STRING_AGG(DISTINCT SUBSTRING(CR.Name FROM 1 FOR 10), ',') FILTER (WHERE CR.Name IS NOT NULL AND PH.PostHistoryTypeId = 10) AS AllCloseReasons,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CR.Id::varchar -- Assuming CloseReasonId is in PostHistory.Comment
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY P.Id, P.Title, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.ViewCount, P.Score, P.OwnerUserId, P.AcceptedAnswerId, P.ParentId, P.Tags, P.ClosedDate, P.CommunityOwnedDate
),
TagPerformance AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS TaggedPostCount,
        AVG(P.Score) AS AvgTagScore,
        MAX(P.CreationDate) AS LatestTagPostDate
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY TagName
    HAVING COUNT(DISTINCT P.Id) > 50 -- Only consider tags with significant usage
)
SELECT
    UE.DisplayName AS AuthorName,
    UE.Reputation,
    PHM.Title AS PostTitle,
    PHM.PostCreationDate,
    PHM.PostScore,
    PHM.ViewCount,
    PHM.PostStatus,
    PHM.EditCount,
    PHM.CloseVoteCount,
    PHM.AvgCommentScore,
    COALESCE(TopPostTag.TagName_parsed, 'untagged') AS TopPostTag,
    TP.AvgTagScore AS TopTagAvgScore,
    COALESCE(
        (SELECT MAX(V.CreationDate)
         FROM Votes V
         WHERE V.PostId = PHM.PostId AND V.VoteTypeId = 2 -- UpVote
         AND V.CreationDate > PHM.PostCreationDate),
        PHM.PostCreationDate
    ) AS LatestUpvoteDate,
    COALESCE(
        (SELECT AVG(LENGTH(C_sub.Text))
         FROM Comments C_sub
         WHERE C_sub.PostId = PHM.PostId
         AND C_sub.CreationDate > PHM.PostCreationDate + INTERVAL '1 hour'
         AND C_sub.UserId = PHM.OwnerUserId),
        0.0
    ) AS AvgOwnerCommentLengthAfter1Hr,
    DENSE_RANK() OVER (PARTITION BY UE.UserId ORDER BY PHM.PostScore DESC, PHM.ViewCount DESC) AS RankWithinUserPosts,
    SUM(CASE WHEN PHM.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY UE.UserId ORDER BY PHM.PostCreationDate) AS CumulativeQuestionCount,
    COALESCE(
        (PHM.PostScore - UE.AvgUserPostScore) / NULLIF(PHM.ViewCount, 0),
        0.0
    ) AS ScorePerViewDeviation,
    PHM.AllCloseReasons,
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = PHM.PostId AND PL.LinkTypeId = 3 -- Duplicate
    ) AS IsDuplicateSource,
    CASE
        WHEN PHM.PostStatus = 'Closed' AND PHM.AllCloseReasons LIKE '%Duplicate%' THEN 'Closed-Duplicate'
        WHEN PHM.PostStatus = 'Closed' AND PHM.AllCloseReasons LIKE '%Off-topic%' THEN 'Closed-OffTopic'
        WHEN PHM.PostStatus = 'Open' AND PHM.TotalHistoryEntries > 5 AND PHM.EditCount > 2 THEN 'HighlyEdited-Open'
        ELSE 'Other'
    END AS PostCategoryFlag,
    REPLACE(REPLACE(PHM.Title, 'SQL', 'Database'), 'Query', 'Statement') AS TransformedTitle,
    (SELECT COUNT(DISTINCT B_sub.Id)
     FROM Badges B_sub
     WHERE B_sub.UserId = UE.UserId
     AND B_sub.Date < PHM.PostCreationDate
     AND B_sub.Class = 1 -- Gold Badges
    ) AS GoldBadgesBeforePost,
    PHM.Tags,
    TP.TaggedPostCount,
    (SELECT TaggedPostCount FROM TagPerformance WHERE TagName = 'sql' LIMIT 1) AS SqlTagGlobalCount -- uncorrelated subquery for a fixed tag's performance baseline
FROM UserEngagementSummary UE
INNER JOIN PostHistoricalMetrics PHM ON UE.UserId = PHM.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join to get top tag for each post
    SELECT TagName_parsed
    FROM UNNEST(string_to_array(SUBSTRING(PHM.Tags, 2, LENGTH(PHM.Tags)-2), '><')) AS TagName_parsed
    JOIN Tags T_lookup ON TagName_parsed = T_lookup.TagName
    ORDER BY T_lookup.Count DESC
    LIMIT 1
) AS TopPostTag ON TRUE
LEFT JOIN TagPerformance TP ON TopPostTag.TagName_parsed = TP.TagName
WHERE UE.Reputation > 1000
AND PHM.PostScore > 5
AND PHM.ViewCount > 100
AND PHM.LastActivityDate BETWEEN UE.LastAccess - INTERVAL '1 year' AND UE.LastAccess + INTERVAL '1 month'
AND EXISTS ( -- Correlated subquery for users with comments on related posts
    SELECT 1
    FROM Comments C_inner
    JOIN Posts P_inner ON C_inner.PostId = P_inner.Id
    WHERE C_inner.UserId = UE.UserId
    AND P_inner.ParentId = PHM.ParentId -- If PHM is an answer, check comments on its question
    AND P_inner.Id <> PHM.PostId -- Exclude the current post
)
AND NOT EXISTS ( -- Correlated subquery for posts without specific destructive history
    SELECT 1
    FROM PostHistory PH_neg
    WHERE PH_neg.PostId = PHM.PostId
    AND PH_neg.PostHistoryTypeId IN (12, 13) -- Deleted or Undeleted
)
UNION ALL
SELECT
    'Anonymous Community' AS AuthorName,
    0 AS Reputation,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    'Unattributed Orphaned' AS PostStatus,
    0 AS EditCount,
    0 AS CloseVoteCount,
    0.0 AS AvgCommentScore,
    NULL AS TopPostTag,
    0.0 AS TopTagAvgScore,
    NULL AS LatestUpvoteDate,
    0.0 AS AvgOwnerCommentLengthAfter1Hr,
    0 AS RankWithinUserPosts,
    0 AS CumulativeQuestionCount,
    0.0 AS ScorePerViewDeviation,
    NULL AS AllCloseReasons,
    FALSE AS IsDuplicateSource,
    'Community-Orphan' AS PostCategoryFlag,
    REPLACE(P.Title, 'Question', 'Inquiry') AS TransformedTitle,
    0 AS GoldBadgesBeforePost,
    P.Tags,
    0 AS TaggedPostCount,
    (SELECT TaggedPostCount FROM TagPerformance WHERE TagName = 'community' LIMIT 1) AS SqlTagGlobalCount
FROM Posts P
INNER JOIN Comments C ON P.Id = C.PostId
WHERE P.OwnerUserId IS NULL -- Posts by community or deleted users
AND C.UserId IS NULL -- Comments by truly anonymous users (not just deleted)
AND P.PostTypeId = 1 -- Only questions
AND P.Score < 0 -- Negatively scored posts
AND LENGTH(C.Text) > 500 -- Long anonymous comments
AND P.CreationDate BETWEEN '2021-01-01' AND '2022-12-31'
ORDER BY PostCreationDate DESC, Reputation DESC
LIMIT 1000;