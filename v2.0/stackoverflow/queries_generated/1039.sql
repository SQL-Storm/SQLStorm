-- {"query": "1039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2845} 
WITH PostClosedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 10 -- Post Closed
),
PostReopenedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 11 -- Post Reopened
),
PostDeletedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 12 -- Post Deleted
),
PostUndeletedEvents AS (
    SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 13 -- Post Undeleted
),
ControversialPosts AS (
    -- CTE 1: Identifies posts that have gone through cycles of closing/reopening or deleting/undeleting
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
    -- CTE 2: Summarizes user activity, badges, and calculates engagement metrics
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
        EXTRACT(DAY FROM (NOW() - U.CreationDate)) AS DaysSinceCreation
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT P.Id) > 5 AND U.Reputation > 1000 -- Filter out less active/reputable users early
),
PostVersionHistory AS (
    -- CTE 3: Tracks significant changes for posts, including unique editors and event timelines
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryUserId,
        PH.Comment AS HistoryComment,
        PH.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS HistorySequenceNum,
        LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousHistoryDate,
        COUNT(DISTINCT PH.UserId) OVER (PARTITION BY PH.PostId) AS UniqueEditors
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13) -- Initial content, edits, closed/reopened, deleted/undeleted
),
PostDetailedMetrics AS (
    -- CTE 4: Aggregates post-specific metrics, including edit counts and close status
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
        PVH.UniqueEditors,
        SUM(CASE WHEN PVH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(CASE WHEN PVH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PVH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(PVH.HistoryDate) AS LastHistoryEventDate,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS TotalFavorites -- Correlated subquery for favorite counts
    FROM Posts P
    LEFT JOIN PostVersionHistory PVH ON P.Id = PVH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.AcceptedAnswerId, P.ParentId, P.CreationDate, P.Score,
        P.ViewCount, P.Body, P.OwnerUserId, P.Title, P.Tags, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.ClosedDate, PVH.UniqueEditors
),
PopularTagStats AS (
    -- CTE 5: Calculates statistics for frequently used and high-scoring tags
    SELECT
        TRIM(REPLACE(REPLACE(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')), '<', ''), '>', '')) AS TagName,
        COUNT(P.Id) AS TagPostCount,
        AVG(P.Score) AS AvgTagScore,
        SUM(P.ViewCount) AS TotalTagViews
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags != '' AND P.PostTypeId = 1
    GROUP BY TagName
    HAVING COUNT(P.Id) > 100 AND AVG(P.Score) > 5
),
PostPrimaryTag AS (
    -- CTE 6: Extracts the first tag from each post for targeted joins
    SELECT
        P.Id AS PostId,
        TRIM(REPLACE(REPLACE(substring(P.Tags, 2, position('>' IN P.Tags) - 2), '<', ''), '>', '')) AS PrimaryTagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND P.Tags LIKE '<%>%<' -- Ensure it has at least one full tag
)
-- Main query: Combines data from all CTEs and applies complex logic for filtering and analysis
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
    EXTRACT(EPOCH FROM (NOW() - PDM.PostCreationDate)) / (3600.0 * 24.0) AS DaysOld, -- Age in days, as a float
    FIRST_VALUE(PH_initial.HistoryText) OVER (PARTITION BY PDM.PostId ORDER BY PH_initial.HistoryDate) AS InitialBodyContent,
    LAST_VALUE(PH_latest.HistoryText) OVER (PARTITION BY PDM.PostId ORDER BY PH_latest.HistoryDate DESC) AS LatestBodyContent, -- Using DESC to get truly last
    RANK() OVER (PARTITION BY UE.HasGoldBadge ORDER BY UE.Reputation DESC, UE.TotalPosts DESC) AS UserEngagementRank,
    DENSE_RANK() OVER (ORDER BY PDM.PostScore DESC, PDM.ViewCount DESC, PDM.FavoriteCount DESC) AS GlobalPostRank,
    SUM(PDM.TotalFavorites) OVER (PARTITION BY UE.UserId) AS UserTotalFavoritesAcrossPosts
FROM UserEngagement UE
INNER JOIN PostDetailedMetrics PDM ON UE.UserId = PDM.OwnerUserId
LEFT JOIN Posts P ON PDM.PostId = P.Id -- Join back to original Posts for fields like ContentLicense
LEFT JOIN PostPrimaryTag PPT ON PDM.PostId = PPT.PostId
LEFT JOIN PopularTagStats PTS ON PPT.PrimaryTagName = PTS.TagName
LEFT JOIN ControversialPosts CP ON PDM.PostId = CP.PostId
LEFT JOIN PostVersionHistory PH_initial ON PDM.PostId = PH_initial.PostId AND PH_initial.PostHistoryTypeId = 2 -- Initial Body
LEFT JOIN PostVersionHistory PH_latest ON PDM.PostId = PH_latest.PostId AND PH_latest.PostHistoryTypeId = 5 -- Latest Body (edit)
WHERE
    UE.Reputation > 7500 -- High-reputation users
    AND UE.DaysSinceCreation >= 730 -- Active for at least two years
    AND PDM.PostCreationDate BETWEEN '2022-01-01' AND '2023-12-31' -- Posts created in a specific two-year window
    AND (PDM.Tags LIKE '%<java>%' OR PDM.Tags LIKE '%<python>%' OR PDM.Tags LIKE '%<javascript>%') -- Posts related to popular programming languages
    AND PDM.UniqueEditors >= 3 -- Posts edited by at least three distinct users (including owner)
    AND (PDM.WasClosed = 0 OR PDM.WasReopened = 1 OR CP.IsControversial = TRUE) -- Not closed, or was reopened, or otherwise controversial
    AND P.ContentLicense IS NOT NULL -- Ensures license information is present
    AND PDM.PostScore > 15 -- Only reasonably scored posts
    AND PDM.ViewCount > 500 -- Only posts with significant views
    AND EXISTS (
        -- Correlated subquery: Check if the user has a gold badge, or a silver/bronze tag-based badge for one of the primary tags
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