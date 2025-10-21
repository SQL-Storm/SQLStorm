-- {"query": "19097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2947} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN P.PostTypeId NOT IN (1, 2) THEN 1 ELSE 0 END) AS OtherPostCount,
        SUM(P.Score) AS TotalPostScoreOwned,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceivedByPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceivedByPosts,
        COALESCE(U.Location, 'Unspecified Location') AS UserLocation,
        CASE
            WHEN U.AboutMe IS NOT NULL AND (U.AboutMe LIKE '%SQL%' OR LOWER(U.AboutMe) LIKE '%database%' OR U.AboutMe LIKE '%developer%') THEN TRUE
            ELSE FALSE
        END AS HasTechKeywordsInAboutMe,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.CreationDate)) / (3600 * 24 * 365.25) AS YearsOnPlatform,
        CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes + 1, 0) AS UserGivenVoteRatio, -- Add 1 to downvotes to avoid division by zero if DownVotes is 0
        RANK() OVER (ORDER BY U.Reputation DESC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY U.CreationDate) AS CreationDateDecile
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- UpMod, DownMod received on posts owned by user
    WHERE U.Reputation > 500
      AND U.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '90 days'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Location, U.AboutMe, U.UpVotes, U.DownVotes
),
PostDetailStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        STRING_AGG(DISTINCT T_unnest.TagName, ', ') FILTER (WHERE T_unnest.TagName IS NOT NULL) AS AssociatedTags,
        (SELECT MAX(C.CreationDate) FROM Comments AS C WHERE C.PostId = P.Id) AS LastCommentDate, -- Correlated subquery
        (P.Score + COALESCE(P.CommentCount, 0) * 2 + COALESCE(P.FavoriteCount, 0) * 5) * 1.0 / NULLIF(P.ViewCount, 0) AS EngagementRatio,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
            WHEN P.AnswerCount > 0 THEN 'Has Unaccepted Answers'
            ELSE 'No Answers Yet'
        END AS AnswerStatus,
        LAG(P.LastEditDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostEditDate,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY (P.Score + COALESCE(P.FavoriteCount, 0)) DESC, P.ViewCount DESC) AS UserPostRankByEngagement,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS EditCount, -- Edit Title, Body, Tags
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId ORDER BY P.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreByPostType,
        COALESCE(PL.LinkTypeId, 0) AS HasRelatedLink -- 1 = Linked, 3 = Duplicate, 0 = No Link
    FROM Posts AS P
    LEFT JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN (SELECT PostId, RelatedPostId, LinkTypeId FROM PostLinks WHERE LinkTypeId IN (1,3)) AS PL ON P.Id = PL.PostId
    -- Unnest tags for proper aggregation
    LEFT JOIN (
        SELECT Id, unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND length(Tags) > 2
    ) AS T_unnest ON T_unnest.Id = P.Id
    WHERE P.PostTypeId IN (1, 2) -- Questions or Answers
      AND P.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 year'
      AND P.Score >= 0
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.AcceptedAnswerId, P.LastEditDate, PL.LinkTypeId
),
RecentPostModerationActivity AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.UserId AS EditorUserId,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryDetails,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_history,
        COALESCE(CRT.Name, 'N/A') AS CloseReasonParsed -- Use COALESCE for NULL safety
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes AS CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CRT.Id = CAST(PH.Comment AS SMALLINT)
    WHERE PH.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
)
-- UNION ALL Part 1: User-Centric View
SELECT
    'User_Summary' AS RecordType,
    UAS.UserId AS EntityId,
    UAS.DisplayName AS EntityName,
    CAST(UAS.Reputation AS NUMERIC) AS PrimaryScore,
    UAS.UserCreationDate AS EntityCreationDate,
    UAS.YearsOnPlatform AS AgeInUnits,
    CAST(UAS.TotalPosts AS BIGINT) AS Metric_TotalPosts,
    CAST(UAS.QuestionCount AS BIGINT) AS Metric_Questions,
    CAST(UAS.AnswerCount AS BIGINT) AS Metric_Answers,
    CAST(UAS.TotalBadges AS BIGINT) AS Metric_Badges,
    CAST(UAS.UpVotesReceivedByPosts AS NUMERIC) AS Metric_Numerical_1,
    PDS.PostId AS RelatedEntityId,
    PDS.Title AS RelatedEntityTitle,
    CAST(PDS.PostScore AS NUMERIC) AS RelatedEntityScore,
    PDS.EngagementRatio AS RelatedEntityNumerical_1,
    PDS.AssociatedTags AS RelatedEntityTags,
    RMA.HistoryTypeName AS LatestModerationAction,
    RMA.HistoryDate AS LatestModerationActionDate,
    RMA.CloseReasonParsed AS LatestCloseReason,
    UAS.UserLocation AS EntityLocation,
    UAS.HasTechKeywordsInAboutMe AS EntityBoolean_1,
    UAS.UserGivenVoteRatio AS EntityNumerical_2,
    AVG(PDS.RollingAvgPostScoreByPostType) OVER (PARTITION BY UAS.UserId) AS UserAvgRollingPostScore,
    CAST(COUNT(DISTINCT RMA.HistoryTypeName) OVER (PARTITION BY UAS.UserId) AS BIGINT) AS Metric_DistinctModerationActions
FROM UserActivitySummary AS UAS
LEFT JOIN PostDetailStats AS PDS ON UAS.UserId = PDS.OwnerUserId AND PDS.UserPostRankByEngagement = 1
LEFT JOIN RecentPostModerationActivity AS RMA ON PDS.PostId = RMA.PostId AND RMA.rn_latest_history = 1
WHERE UAS.YearsOnPlatform > 2
  AND UAS.TotalPosts > 10
  AND (PDS.EngagementRatio IS NULL OR PDS.EngagementRatio > 0.3)
  AND UAS.HasTechKeywordsInAboutMe = TRUE
  AND UAS.DisplayName LIKE 'S%t'
  AND (RMA.HistoryTypeName IS NOT NULL OR PDS.PostId IS NULL)
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.YearsOnPlatform, UAS.TotalPosts,
    UAS.QuestionCount, UAS.AnswerCount, UAS.TotalBadges, UAS.UpVotesReceivedByPosts, UAS.UserLocation,
    UAS.HasTechKeywordsInAboutMe, UAS.UserGivenVoteRatio, PDS.PostId, PDS.Title, PDS.PostScore,
    PDS.EngagementRatio, PDS.AssociatedTags, RMA.HistoryTypeName, RMA.HistoryDate, RMA.CloseReasonParsed

UNION ALL

-- UNION ALL Part 2: Post-Centric View
SELECT
    'Post_Summary' AS RecordType,
    PDS.PostId AS EntityId,
    PDS.Title AS EntityName,
    CAST(PDS.PostScore AS NUMERIC) AS PrimaryScore,
    PDS.PostCreationDate AS EntityCreationDate,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - PDS.PostCreationDate)) / (3600 * 24 * 365.25) AS AgeInUnits,
    CAST(PDS.ViewCount AS BIGINT) AS Metric_TotalPosts,
    CAST(PDS.CommentCount AS BIGINT) AS Metric_Questions,
    CAST(PDS.AnswerCount AS BIGINT) AS Metric_Answers,
    CAST(PDS.FavoriteCount AS BIGINT) AS Metric_Badges,
    PDS.EngagementRatio AS Metric_Numerical_1,
    PDS.OwnerUserId AS RelatedEntityId,
    UAS.DisplayName AS RelatedEntityTitle,
    CAST(UAS.Reputation AS NUMERIC) AS RelatedEntityScore,
    NULL AS RelatedEntityNumerical_1, -- Not applicable for this side of the union
    PDS.AssociatedTags AS RelatedEntityTags,
    RMA.HistoryTypeName AS LatestModerationAction,
    RMA.HistoryDate AS LatestModerationActionDate,
    RMA.CloseReasonParsed AS LatestCloseReason,
    PDS.PostTypeName AS EntityLocation,
    (PDS.PostScore > 50) AS EntityBoolean_1,
    CAST((PDS.HasRelatedLink > 0) AS NUMERIC) AS EntityNumerical_2, -- Convert boolean to numeric for compatibility
    PDS.RollingAvgPostScoreByPostType AS UserAvgRollingPostScore, -- Renamed, this is the post's rolling avg
    CAST(PDS.EditCount AS BIGINT) AS Metric_DistinctModerationActions
FROM PostDetailStats AS PDS
LEFT JOIN UserActivitySummary AS UAS ON PDS.OwnerUserId = UAS.UserId
LEFT JOIN RecentPostModerationActivity AS RMA ON PDS.PostId = RMA.PostId AND RMA.rn_latest_history = 1
WHERE PDS.PostTypeId = 1
  AND PDS.EngagementRatio > 1.0
  AND PDS.PostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
  AND PDS.AssociatedTags LIKE '%database%'
  AND PDS.PostScore > 100
  AND (RMA.HistoryTypeName IS NULL OR RMA.HistoryTypeName NOT LIKE '%Deleted%')
ORDER BY PrimaryScore DESC, AgeInUnits ASC
LIMIT 1000;
