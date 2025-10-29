-- {"query": "1149.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2189} 

WITH UserEngagement AS (
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
        COUNT(DISTINCT C.Id) AS TotalComments,
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(P.Id) > 0 OR COUNT(C.Id) > 0
),
PostVersionHistory AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(PH.CreationDate) AS FirstHistoryDate,
        (SELECT Name FROM CloseReasonTypes WHERE Id = (
            SELECT CAST(Comment AS smallint)
            FROM PostHistory
            WHERE PostId = PH.PostId AND PostHistoryTypeId = 10 AND Comment IS NOT NULL
            GROUP BY Comment
            ORDER BY COUNT(*) DESC
            LIMIT 1
        )) AS MostCommonCloseReason
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.Tags,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
TagCounts AS (
    SELECT
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS PostsWithTagCount,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.Score) AS AverageTagScore,
        MIN(P.CreationDate) AS FirstTagPostDate,
        MAX(P.CreationDate) AS LastTagPostDate
    FROM TagAnalysis AS TA
    JOIN Posts AS P ON TA.PostId = P.Id
    GROUP BY TA.TagName
),
RecentSignificantPostEvents AS (
    SELECT
        PH.PostId,
        'Recently Edited by Other' AS EventType,
        PH.CreationDate AS EventDate,
        PH.UserId AS EventUserId
    FROM PostHistory AS PH
    WHERE
        PH.PostHistoryTypeId IN (4, 5, 6)
        AND PH.CreationDate >= NOW() - INTERVAL '30 days'
        AND PH.UserId IS NOT NULL
    UNION ALL
    SELECT
        PH.PostId,
        CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Recently Closed' ELSE 'Recently Reopened' END AS EventType,
        PH.CreationDate AS EventDate,
        PH.UserId AS EventUserId
    FROM PostHistory AS PH
    WHERE
        PH.PostHistoryTypeId IN (10, 11)
        AND PH.CreationDate >= NOW() - INTERVAL '30 days'
)
SELECT
    P.Id AS PostID,
    P.Title,
    PT.Name AS PostTypeName,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount,
    P.CreationDate AS PostCreationDate,
    P.LastActivityDate,
    COALESCE(P.ClosedDate, '9999-12-31 23:59:59') AS ClosedOrFutureDate,
    P.CommunityOwnedDate,
    LENGTH(P.Body) AS BodyLength,
    SUBSTRING(P.Body FROM 1 FOR 200) AS BodySnippet,
    UE.DisplayName AS OwnerDisplayName,
    UE.Reputation AS OwnerReputation,
    UE.TotalQuestions AS OwnerTotalQuestions,
    UE.TotalAnswers AS OwnerTotalAnswers,
    PVH.EditCount,
    PVH.CloseCount,
    PVH.ReopenCount,
    PVH.MostCommonCloseReason,
    TC.PostsWithTagCount AS PrimaryTagTotalPosts,
    TC.AverageTagScore AS PrimaryTagAvgScore,
    EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 86400.0 AS DaysSinceCreationToLastActivity,
    (
        SELECT AVG(A.Score)
        FROM Posts AS A
        WHERE A.ParentId = P.Id AND A.PostTypeId = 2
    ) AS AvgAnswerScoreForQuestion,
    (
        SELECT AVG(ViewCount)
        FROM Posts
        WHERE PostTypeId = 1
    ) AS GlobalAvgQuestionViewCount,
    ROW_NUMBER() OVER (PARTITION BY PT.Name ORDER BY P.Score DESC, P.CreationDate DESC) AS PostTypeScoreRank,
    SUM(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS OwnerCumulativeScore,
    TRIM(SUBSTRING(P.Tags FROM 2 FOR COALESCE(NULLIF(POSITION('>' IN SUBSTRING(P.Tags FROM 2)), 0) - 1, LENGTH(P.Tags) - 2))) AS PrimaryTag,
    CASE
        WHEN P.ClosedDate IS NOT NULL AND PVH.CloseCount > 1 THEN 'Frequently Closed'
        WHEN P.Score >= 100 AND P.ViewCount >= 10000 AND UE.GoldBadges >= 1 THEN 'Highly Influential Post'
        WHEN P.AnswerCount > 5 AND (SELECT AVG(A.Score) FROM Posts AS A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) > 5 THEN 'Well-Answered & Popular'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Managed'
        ELSE 'Standard Activity'
    END AS PostStatusCategory,
    EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS HasLinkedPosts,
    EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS HasDuplicatePosts,
    CASE WHEN UE.Reputation >= 50000 AND UE.GoldBadges >= 5 THEN 'Elite User' ELSE 'Regular User' END AS OwnerReputationClass,
    CASE WHEN RSPA.PostId IS NOT NULL THEN 'Has Recent Significant Events' ELSE 'No Recent Significant Events' END AS RecentEventStatus
FROM Posts AS P
JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
LEFT JOIN UserEngagement AS UE ON P.OwnerUserId = UE.UserId
LEFT JOIN PostVersionHistory AS PVH ON P.Id = PVH.PostId
LEFT JOIN TagCounts AS TC ON TRIM(SUBSTRING(P.Tags FROM 2 FOR COALESCE(NULLIF(POSITION('>' IN SUBSTRING(P.Tags FROM 2)), 0) - 1, LENGTH(P.Tags) - 2))) = TC.TagName
LEFT JOIN (SELECT DISTINCT PostId FROM RecentSignificantPostEvents) AS RSPA ON P.Id = RSPA.PostId
WHERE
    P.CreationDate >= '2023-01-01 00:00:00'
    AND P.PostTypeId IN (1, 2)
    AND P.Score IS NOT NULL AND P.Score > 0
    AND (
        P.OwnerUserId IS NOT NULL
        OR P.CommunityOwnedDate IS NOT NULL
    )
    AND P.Body LIKE '%sql%'
    AND (P.ViewCount > 500 OR P.AnswerCount > 0)
    AND (UE.TotalBadges > 0 OR UE.Reputation > 1000)
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory
        WHERE PostId = P.Id AND PostHistoryTypeId = 12
    )
ORDER BY
    P.Score DESC,
    P.LastActivityDate DESC,
    OwnerReputation DESC
LIMIT 1000;
