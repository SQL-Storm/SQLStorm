-- {"query": "1039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2845}
WITH PostClosedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 10
),
PostReopenedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 11
),
PostDeletedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 12
),
PostUndeletedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 13
),
ControversialPosts AS (
    SELECT
        pce.PostId,
        'ClosedReopened' AS ControversyType,
        TRUE AS IsControversial
    FROM PostClosedEvents pce
    INNER JOIN PostReopenedEvents pre ON pce.PostId = pre.PostId
    UNION ALL
    SELECT
        pde.PostId,
        'DeletedUndeleted' AS ControversyType,
        TRUE AS IsControversial
    FROM PostDeletedEvents pde
    INNER JOIN PostUndeletedEvents pue ON pde.PostId = pue.PostId
),
UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        MAX(P.LastActivityDate) AS LastActivityOnPost,
        MAX(C.CreationDate) AS LastActivityOnComment,
        CAST(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) AS integer) AS DaysSinceCreation
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 5 AND U.Reputation > 1000
),
PostVersionHistory AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryUserId,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS HistorySequenceNum,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate,
        COUNT(*) OVER (PARTITION BY PH.PostId) AS TotalHistoryEvents,
        COUNT(PH.UserId) OVER (PARTITION BY PH.PostId) AS EditorsIncludingDuplicates
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13)
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.Body,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        COALESCE(PVH_calcs.UniqueEditors, 0) AS UniqueEditors,
        SUM(CASE WHEN PVH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(CASE WHEN PVH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PVH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(PVH.HistoryDate) AS LastHistoryEventDate,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavorites
    FROM Posts P
    LEFT JOIN PostVersionHistory PVH ON P.Id = PVH.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(DISTINCT UserId) AS UniqueEditors
        FROM PostHistory
        GROUP BY PostId
    ) PVH_calcs ON P.Id = PVH_calcs.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.AcceptedAnswerId, P.ParentId, P.CreationDate, P.Score,
        P.ViewCount, P.Body, P.OwnerUserId, P.Title, P.Tags, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.ClosedDate, PVH_calcs.UniqueEditors
),
-- split tags into rows in a dialect-neutral way: use a derived table that replaces angle brackets and splits by '><' via recursive CTE
PostTags AS (
    SELECT
        P.Id AS PostId,
        TRIM(t.tag) AS TagName
    FROM Posts P
    JOIN (
        -- generate tag rows by repeatedly extracting between '<' and '>'
        SELECT PostId,
               CASE WHEN tag = '' THEN NULL ELSE tag END AS tag
        FROM (
            SELECT
                PT.PostId,
                regexp_split_to_table(PT.TagsClean, '><') AS tag
            FROM (
                SELECT Id AS PostId,
                       REPLACE(REPLACE(SUBSTRING(T.Tags FROM 2 FOR CHAR_LENGTH(T.Tags) - 2), '><', '><'), '><', '><') AS TagsClean,
                       T.Tags
                FROM Posts T
                WHERE T.Tags IS NOT NULL AND T.Tags <> '' AND T.PostTypeId = 1
            ) PT
        ) x
    ) t ON P.Id = t.PostId
),
PopularTagStats AS (
    SELECT
        TagName,
        COUNT(DISTINCT P.Id) AS TagPostCount,
        AVG(P.Score) AS AvgTagScore,
        SUM(P.ViewCount) AS TotalTagViews
    FROM Posts P
    JOIN PostTags PT ON P.Id = PT.PostId
    WHERE P.PostTypeId = 1
    GROUP BY TagName
    HAVING COUNT(DISTINCT P.Id) > 100 AND AVG(P.Score) > 5
),
PostPrimaryTag AS (
    SELECT
        P.Id AS PostId,
        TRIM(REPLACE(REPLACE(SUBSTRING(P.Tags FROM 2 FOR (POSITION('>' IN P.Tags) - 2)), '<', ''), '>', '')) AS PrimaryTagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags LIKE '<%>%<%'
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPosts,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalPostScore,
    UE.TotalComments,
    UE.TotalBadges,
    UE.HasGoldBadge,
    PDM.PostId,
    PDM.PostCreationDate,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.Title,
    PDM.Tags,
    PDM.UniqueEditors,
    PDM.EditCount,
    PDM.WasClosed,
    PDM.WasReopened,
    COALESCE(UE.LastActivityOnPost, UE.LastActivityOnComment, UE.UserCreationDate) AS LatestActivityDate,
    CASE
        WHEN PDM.PostScore >= 100 AND PDM.ViewCount >= 10000 THEN 'Viral'
        WHEN PDM.PostScore >= 50 AND PDM.ViewCount >= 5000 THEN 'Highly Engaged'
        WHEN PDM.PostScore >= 10 THEN 'Popular'
        ELSE 'Niche'
    END AS PostPopularityCategory,
    P.ContentLicense,
    PTS.AvgTagScore AS PrimaryTagAvgScore,
    PTS.TotalTagViews AS PrimaryTagTotalViews,
    COALESCE(CP.ControversyType, 'None') AS PostControversyType,
    COALESCE(CP.IsControversial, FALSE) AS IsControversial,
    (SELECT COUNT(V_inner.Id) FROM Votes V_inner WHERE V_inner.PostId = PDM.PostId AND V_inner.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(V_inner.Id) FROM Votes V_inner WHERE V_inner.PostId = PDM.PostId AND V_inner.VoteTypeId = 3) AS DownVoteCount,
    (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PDM.PostCreationDate)) / (3600.0 * 24.0)) AS DaysOld,
    PH_initial.HistoryText AS InitialBodyContent,
    PH_latest.HistoryText AS LatestBodyContent,
    RANK() OVER (PARTITION BY UE.HasGoldBadge ORDER BY UE.Reputation DESC, UE.TotalPosts DESC) AS UserEngagementRank,
    DENSE_RANK() OVER (ORDER BY PDM.PostScore DESC, PDM.ViewCount DESC, PDM.FavoriteCount DESC) AS GlobalPostRank,
    SUM(PDM.TotalFavorites) OVER (PARTITION BY UE.UserId) AS UserTotalFavoritesAcrossPosts
FROM UserEngagement UE
INNER JOIN PostDetailedMetrics PDM ON UE.UserId = PDM.OwnerUserId
LEFT JOIN Posts P ON PDM.PostId = P.Id
LEFT JOIN PostPrimaryTag PPT ON PDM.PostId = PPT.PostId
LEFT JOIN PopularTagStats PTS ON PPT.PrimaryTagName = PTS.TagName
LEFT JOIN ControversialPosts CP ON PDM.PostId = CP.PostId
LEFT JOIN PostVersionHistory PH_initial ON PDM.PostId = PH_initial.PostId AND PH_initial.PostHistoryTypeId = 2
LEFT JOIN PostVersionHistory PH_latest ON PDM.PostId = PH_latest.PostId AND PH_latest.PostHistoryTypeId = 5
WHERE
    UE.Reputation > 7500
    AND UE.DaysSinceCreation >= 730
    AND PDM.PostCreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-12-31'
    AND (PDM.Tags LIKE '%<java>%' OR PDM.Tags LIKE '%<python>%' OR PDM.Tags LIKE '%<javascript>%')
    AND PDM.UniqueEditors >= 3
    AND (PDM.WasClosed = 0 OR PDM.WasReopened = 1 OR COALESCE(CP.IsControversial, FALSE) = TRUE)
    AND P.ContentLicense IS NOT NULL
    AND PDM.PostScore > 15
    AND PDM.ViewCount > 500
    AND EXISTS (
        SELECT 1
        FROM Badges B_sub
        WHERE B_sub.UserId = UE.UserId
          AND (B_sub.Class = 1
               OR (B_sub.Class IN (2, 3) AND B_sub.TagBased = TRUE AND LOWER(B_sub.Name) IN (LOWER(PPT.PrimaryTagName), 'java', 'python', 'javascript')))
    )
ORDER BY
    UserEngagementRank ASC,
    GlobalPostRank ASC,
    PDM.PostCreationDate DESC
LIMIT 1000;