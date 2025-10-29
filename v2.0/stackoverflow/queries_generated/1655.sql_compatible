WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.CommentCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        (CASE WHEN P.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END) AS IsClosed,
        (
            SELECT Text
            FROM Comments c2
            WHERE c2.PostId = P.Id
            ORDER BY c2.CreationDate DESC
            LIMIT 1
        ) AS MostRecentCommentText,
        CASE WHEN P.PostTypeId = 1 THEN
            (
                SELECT AVG(A.Score)
                FROM Posts A
                WHERE A.ParentId = P.Id AND A.PostTypeId = 2 AND A.CreationDate > (P.CreationDate - INTERVAL '1 month')
            )
        ELSE NULL END AS AvgRecentAnswerScoreForQuestion
    FROM Posts P
),
PostTagAnalysis AS (
    SELECT
        PD.PostId,
        PD.PostTypeId,
        PD.PostScore,
        PD.ViewCount,
        PD.CommentCount,
        PD.FavoriteCount,
        PD.Title,
        TRIM(UNNEST(string_to_array(SUBSTRING(PD.Tags FROM 2 FOR LENGTH(PD.Tags) - 2), '><'))) AS TagName,
        PD.PostCreationDate
    FROM PostDetails PD
    WHERE PD.Tags IS NOT NULL AND LENGTH(PD.Tags) > 2
),
TagPerformance AS (
    SELECT
        TPA.TagName,
        COUNT(DISTINCT TPA.PostId) AS TagPostCount,
        AVG(TPA.PostScore) AS AvgTagScore,
        SUM(TPA.ViewCount) AS TotalTagViewCount,
        SUM(TPA.CommentCount) AS TotalTagCommentCount,
        NTILE(5) OVER (ORDER BY COUNT(DISTINCT TPA.PostId) DESC, AVG(TPA.PostScore) DESC) AS TagPopularityQuintile
    FROM PostTagAnalysis TPA
    GROUP BY TPA.TagName
),
PostHistoryMetrics AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        MIN(PH.CreationDate) AS FirstHistoryDate,
        DATE_PART('day', MAX(PH.CreationDate) - MIN(PH.CreationDate)) AS DaysBetweenFirstAndLastHistory
    FROM PostHistory PH
    GROUP BY PH.PostId
),
CombinedPostData AS (
    SELECT
        PD.PostId,
        PD.PostTypeId,
        PD.Title,
        PD.PostCreationDate,
        PD.LastEditDate,
        PD.LastActivityDate,
        PD.PostScore,
        PD.ViewCount,
        PD.AnswerCount,
        PD.FavoriteCount,
        PD.CommentCount,
        PD.OwnerUserId,
        PD.AcceptedAnswerId,
        PD.ParentId,
        PD.IsClosed,
        PD.MostRecentCommentText,
        COALESCE(PD.AvgRecentAnswerScoreForQuestion, 0) AS AvgRecentAnswerScoreForQuestion,
        COALESCE(PHM.EditCount, 0) AS PostEditCount,
        COALESCE(PHM.CloseVoteCount, 0) AS PostCloseVoteCount,
        COALESCE(PHM.DaysBetweenFirstAndLastHistory, 0) AS PostEditActivityDays,
        (PD.PostScore * 0.5 + PD.ViewCount * 0.1 + COALESCE(PD.AnswerCount, 0) * 0.3 + COALESCE(PD.FavoriteCount, 0) * 0.8 + COALESCE(PD.CommentCount, 0) * 0.6) AS RawEngagementScore,
        LAG(PD.LastActivityDate, 1, PD.PostCreationDate) OVER (PARTITION BY PD.OwnerUserId ORDER BY PD.PostCreationDate) AS PreviousPostActivityDate,
        RANK() OVER (PARTITION BY PD.OwnerUserId ORDER BY PD.PostScore DESC, PD.ViewCount DESC, PD.PostCreationDate DESC) AS RankByUserScore
    FROM PostDetails PD
    LEFT JOIN PostHistoryMetrics PHM ON PD.PostId = PHM.PostId
),
AggregatedLinkData AS (
    SELECT
        PostId,
        COUNT(DISTINCT RelatedPostId) AS LinkedPostCount,
        SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks
    GROUP BY PostId
)
SELECT
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.TotalComments,
    UE.AvgQuestionScore,
    CPD.Title AS PostTitle,
    CPD.PostCreationDate,
    CPD.PostScore,
    CPD.ViewCount,
    CPD.PostEditCount,
    TP.TagName,
    TP.AvgTagScore,
    TP.TagPopularityQuintile,
    CPD.MostRecentCommentText,
    CPD.IsClosed,
    ALD.LinkedPostCount,
    ALD.DuplicateLinkCount,
    (CPD.RawEngagementScore + COALESCE(TP.AvgTagScore / 10.0, 0) + (UE.Reputation / 5000.0) + CPD.AvgRecentAnswerScoreForQuestion * 0.2) AS FinalPostRankScore,
    ROW_NUMBER() OVER (ORDER BY (CPD.RawEngagementScore + COALESCE(TP.AvgTagScore / 10.0, 0) + (UE.Reputation / 5000.0) + CPD.AvgRecentAnswerScoreForQuestion * 0.2) DESC, CPD.PostId) AS GlobalPostRank,
    DENSE_RANK() OVER (PARTITION BY TP.TagName ORDER BY CPD.PostScore DESC, CPD.ViewCount DESC) AS RankWithinTag,
    CASE
        WHEN UE.Reputation > 50000 AND UE.TotalPosts > 100 AND UE.AvgQuestionScore > 10 THEN 'Veteran Power User'
        WHEN UE.Reputation > 10000 AND UE.TotalPosts > 50 THEN 'Established Contributor'
        WHEN UE.Reputation > 1000 OR UE.TotalPosts > 10 THEN 'Active Participant'
        ELSE 'Casual User'
    END AS UserCategory,
    COALESCE(NULLIF(DATE_PART('day', CPD.LastActivityDate - CPD.PostCreationDate), 0), 1) AS DaysActiveSinceCreation,
    UPPER(SUBSTRING(COALESCE(CPD.Title, 'No Title') FROM 1 FOR 1)) || SUBSTRING(COALESCE(CPD.Title, 'No Title') FROM 2) AS CapitalizedTitle,
    REPLACE(COALESCE(CPD.MostRecentCommentText, 'N/A'), 'stack overflow', 'SO') AS SanitizedCommentSnippet,
    CPD.RankByUserScore,
    CASE WHEN CPD.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer' ELSE 'No Accepted Answer' END AS HasAcceptedAnswerStatus,
    DATE_PART('hour', CPD.LastActivityDate - CPD.PreviousPostActivityDate) AS HoursSincePreviousPost
FROM CombinedPostData CPD
INNER JOIN UserEngagement UE ON CPD.OwnerUserId = UE.UserId
LEFT JOIN PostTagAnalysis PTA ON CPD.PostId = PTA.PostId
LEFT JOIN TagPerformance TP ON PTA.TagName = TP.TagName
LEFT JOIN AggregatedLinkData ALD ON CPD.PostId = ALD.PostId
WHERE
    CPD.PostTypeId IN (1, 2)
    AND CPD.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
    AND UE.Reputation > (SELECT AVG(U2.Reputation) FROM Users U2 WHERE U2.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years'))
    AND CPD.CommentCount > 0
    AND (CPD.IsClosed = FALSE OR CPD.PostCloseVoteCount < 3)
    AND (
        CPD.PostScore > 5
        OR
        CPD.FavoriteCount > 0
        OR
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UE.UserId AND LOWER(B.Name) LIKE '%gold%' AND B.Class = 1)
    )
ORDER BY GlobalPostRank ASC, UE.Reputation DESC
LIMIT 10000;