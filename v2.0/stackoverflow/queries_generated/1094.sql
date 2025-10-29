-- {"query": "1094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2560} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.ViewCount) AS AvgPostViewCount,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        U.AboutMe
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.AboutMe
    HAVING COUNT(DISTINCT P.Id) > 5
       AND U.Reputation > 1000
),
PostHistoricalMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        COALESCE(P.AnswerCount, 0) AS ActualAnswerCount,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS TagCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDate,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        SUM(COALESCE(CM.Score, 0)) AS TotalCommentScore,
        (EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0) AS ActivityHoursDuration -- in hours
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Comments AS CM ON P.Id = CM.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.Tags
    HAVING COUNT(DISTINCT PH.Id) > 1
),
RecentPostActivity AS (
    WITH TopRecentUserPosts AS (
        SELECT
            PHM.PostId,
            PHM.OwnerUserId,
            PHM.PostTypeId,
            PHM.PostCreationDate,
            PHM.LastActivityDate,
            PHM.PostScore,
            PHM.PostViewCount,
            PHM.ActualAnswerCount,
            PHM.TagCount,
            PHM.EditCount,
            PHM.CloseHistoryCount,
            PHM.LastClosedDate,
            PHM.UniqueEditors,
            PHM.TotalCommentScore,
            PHM.ActivityHoursDuration,
            ROW_NUMBER() OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.PostCreationDate DESC) AS rn_user_post_desc,
            LAG(PHM.PostCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY PHM.OwnerUserId ORDER BY PHM.PostCreationDate) AS PrevPostCreationDate,
            NTILE(4) OVER (ORDER BY PHM.PostScore DESC, PHM.ViewCount DESC) AS ScoreViewQuartile,
            'TopRecent' AS PostSetCategory
        FROM PostHistoricalMetrics AS PHM
        WHERE PHM.PostCreationDate > '2020-01-01'
    ),
    HighImpactLegacyPosts AS (
        SELECT
            PHM.PostId,
            PHM.OwnerUserId,
            PHM.PostTypeId,
            PHM.PostCreationDate,
            PHM.LastActivityDate,
            PHM.PostScore,
            PHM.PostViewCount,
            PHM.ActualAnswerCount,
            PHM.TagCount,
            PHM.EditCount,
            PHM.CloseHistoryCount,
            PHM.LastClosedDate,
            PHM.UniqueEditors,
            PHM.TotalCommentScore,
            PHM.ActivityHoursDuration,
            NULL::bigint AS rn_user_post_desc,
            NULL::timestamp AS PrevPostCreationDate,
            NULL::int AS ScoreViewQuartile,
            'HighImpactLegacy' AS PostSetCategory
        FROM PostHistoricalMetrics AS PHM
        JOIN UserEngagement AS UE ON PHM.OwnerUserId = UE.UserId
        WHERE UE.Reputation > 50000
          AND PHM.PostScore > 100
          AND PHM.PostTypeId = 1
    )
    SELECT * FROM TopRecentUserPosts WHERE rn_user_post_desc <= 5
    UNION ALL
    SELECT * FROM HighImpactLegacyPosts
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    RPA.PostId,
    P.Title,
    P.Tags,
    RPA.PostCreationDate,
    RPA.PostScore,
    RPA.PostViewCount,
    RPA.ActualAnswerCount,
    RPA.EditCount,
    RPA.UniqueEditors,
    RPA.TotalCommentScore,
    RPA.ActivityHoursDuration,
    COALESCE(RPA.ScoreViewQuartile, 0) AS ScoreViewQuartile, -- Use 0 for legacy posts
    AGE(CURRENT_TIMESTAMP, RPA.PostCreationDate) AS TimeSincePost,
    EXTRACT(DAY FROM (RPA.PostCreationDate - COALESCE(RPA.PrevPostCreationDate, RPA.PostCreationDate))) AS DaysBetweenPosts,
    COALESCE(PL.RelatedPostId, -1) AS LinkedRelatedPostId,
    COALESCE(CLT.Name, 'NOT_CLOSED') AS ClosureReasonType,
    CASE
        WHEN UE.Reputation > 20000 AND RPA.PostScore > 75 THEN 'Elite Impact User Post'
        WHEN UE.Reputation > 10000 AND RPA.EditCount > 5 AND RPA.ActivityHoursDuration > 24*7 THEN 'Highly Active Contributor Post'
        WHEN UE.Reputation > 5000 AND RPA.ActualAnswerCount > 3 THEN 'Engaged Question Owner'
        ELSE 'Regular Activity'
    END AS ActivityCategory,
    (SELECT AVG(SubP.Score) FROM Posts AS SubP WHERE SubP.OwnerUserId = UE.UserId AND SubP.Id != RPA.PostId AND SubP.PostTypeId = RPA.PostTypeId) AS AvgOtherPostScoreByOwnerOfType,
    (SELECT COUNT(DISTINCT B.Name) FROM Badges AS B WHERE B.UserId = UE.UserId AND B.Class = 1 AND B.Date > UE.LastPostDate - INTERVAL '1 year') AS RecentGoldBadgesCount,
    STRING_AGG(T.TagName, '; ') FILTER (WHERE T.TagName IS NOT NULL) AS AssociatedTagNames,
    COALESCE(UE.AboutMe, '') LIKE '%developer%' AS AboutMeMentionsDeveloper,
    RPA.PostSetCategory
FROM UserEngagement AS UE
INNER JOIN RecentPostActivity AS RPA ON UE.UserId = RPA.OwnerUserId
INNER JOIN Posts AS P ON RPA.PostId = P.Id
LEFT JOIN PostLinks AS PL ON RPA.PostId = PL.PostId AND PL.LinkTypeId = 1
LEFT JOIN PostHistory AS PH_Close ON RPA.PostId = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.Id = (
    SELECT MAX(PH2.Id)
    FROM PostHistory AS PH2
    WHERE PH2.PostId = RPA.PostId AND PH2.PostHistoryTypeId = 10
)
LEFT JOIN CloseReasonTypes AS CLT ON PH_Close.Comment IS NOT NULL AND TRY_CAST(PH_Close.Comment AS SMALLINT) = CLT.Id -- Handling potential non-numeric comments
LEFT JOIN (
    SELECT DISTINCT unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName, Id AS PostId
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != '' AND LENGTH(Tags) > 2
) AS PostTags ON PostTags.PostId = P.Id
LEFT JOIN Tags AS T ON PostTags.TagName = T.TagName
WHERE (RPA.PostSetCategory = 'TopRecent' AND RPA.rn_user_post_desc <= 5)
   OR (RPA.PostSetCategory = 'HighImpactLegacy' AND RPA.PostScore > 100)
  AND RPA.PostScore > (SELECT AVG(P_Inner.Score) FROM Posts AS P_Inner WHERE P_Inner.PostTypeId = P.PostTypeId AND P_Inner.CreationDate > CURRENT_DATE - INTERVAL '5 year') -- Compared to recent average
  AND (P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<performance>%')
  AND P.Title IS NOT NULL
  AND P.Body IS NOT NULL
  AND LENGTH(TRIM(P.Body)) > 100
  AND UE.LastPostDate IS NOT NULL
  AND (RPA.CloseHistoryCount = 0 OR RPA.LastClosedDate >= '2023-01-01' OR RPA.PostSetCategory = 'HighImpactLegacy') -- allow old closed legacy posts
  AND UE.AboutMe IS NOT NULL AND POSITION('data' IN LOWER(UE.AboutMe)) > 0
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, RPA.PostId, P.Title, P.Tags, RPA.PostCreationDate, RPA.PostScore, RPA.PostViewCount, RPA.ActualAnswerCount, RPA.EditCount, RPA.UniqueEditors, RPA.TotalCommentScore, RPA.ActivityHoursDuration, RPA.ScoreViewQuartile, RPA.PrevPostCreationDate, UE.LastPostDate, PL.RelatedPostId, CLT.Name, UE.AboutMe, RPA.PostSetCategory
ORDER BY
    UE.Reputation DESC, RPA.PostScore DESC, RPA.PostCreationDate DESC, RPA.PostSetCategory DESC
LIMIT 200;
