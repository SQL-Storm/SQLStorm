-- {"query": "1868.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3347} 

WITH UserProfileSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(U.Location, 'Unspecified') AS UserLocation,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT B.Id) AS TotalBadgesCount,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS GlobalReputationRank,
        STRING_AGG(DISTINCT B.Name, '; ') FILTER (WHERE B.Class = 1) AS GoldBadgeNamesAggregated,
        LEFT(COALESCE(U.AboutMe, ''), 150) AS AboutMeSnippet
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Location, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate, U.AboutMe
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT PH.UserId) AS UniqueEditorsCount,
        MAX(PH.CreationDate) AS LatestHistoryEventDate,
        MIN(PH.CreationDate) AS EarliestHistoryEventDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS ContentEditCount,
        FIRST_VALUE(PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LastContentEditorUserId,
        -- Time from initial post creation (type 1 or 2) to first actual content edit (type 4,5,6)
        EXTRACT(EPOCH FROM (
            MIN(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate END) -
            MIN(CASE WHEN PH.PostHistoryTypeId IN (1,2,3) THEN PH.CreationDate END)
        )) / 3600 AS HoursToFirstEdit,
        -- Detect sequential edits by the same user
        SUM(CASE WHEN PH.UserId = LAG(PH.UserId, 1, PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) THEN 1 ELSE 0 END) AS ConsecutiveEditsBySameUser
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
PostTaggingAnalysis AS (
    SELECT
        P.Id AS PostId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM P.Tags), '><')) AS TagName_Cleaned
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2
),
PostDetailAggregates AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS PostFavoriteCount,
        P.OwnerUserId,
        P.ParentId,
        P.LastActivityDate,
        COALESCE(P.ClosedDate, PHT.LatestHistoryEventDate) AS EffectiveClosedDate,
        COUNT(DISTINCT C.Id) AS ActualCommentsCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ActualUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ActualDownvotesReceived,
        AVG(LENGTH(C.Text)) FILTER (WHERE C.Text IS NOT NULL) AS AvgCommentTextLength,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedLinks,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicateLinks,
        -- Correlated subquery to fetch the content of the most recent comment
        (SELECT C_latest.Text FROM Comments AS C_latest WHERE C_latest.PostId = P.Id ORDER BY C_latest.CreationDate DESC LIMIT 1) AS LatestCommentContent,
        -- Correlated subquery to check if post was ever migrated
        EXISTS (
            SELECT 1 FROM PostHistory AS PH_mig WHERE PH_mig.PostId = P.Id AND PH_mig.PostHistoryTypeId IN (17, 35, 36)
        ) AS WasPostMigrated,
        P.Body AS PostFullBody,
        P.Title
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistoryTimeline AS PHT ON P.Id = PHT.PostId
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.ParentId, P.LastActivityDate, P.ClosedDate, PHT.LatestHistoryEventDate, P.Body, P.Title
),
CombinedPostAndUserAnalytics AS (
    SELECT
        UPS.UserId,
        UPS.DisplayName,
        UPS.UserLocation,
        UPS.Reputation,
        UPS.GlobalReputationRank,
        PDA.PostId,
        PDA.PostTypeName,
        PDA.Title,
        PDA.PostCreationDate,
        PDA.Score,
        PDA.ViewCount,
        PDA.AnswerCount,
        PDA.ActualCommentsCount,
        PDA.PostFavoriteCount,
        PDA.TotalRelatedLinks,
        PDA.TotalDuplicateLinks,
        PDA.LatestCommentContent,
        PDA.WasPostMigrated,
        PDA.EffectiveClosedDate,
        PDA.PostFullBody,
        PDA.LastActivityDate AS PostLastActivityDate,
        PHT.TotalHistoryEvents,
        PHT.UniqueEditorsCount,
        PHT.LatestHistoryEventDate AS PostHistoryLastEditDate,
        PHT.ContentEditCount,
        PHT.HoursToFirstEdit,
        PHT.LastContentEditorUserId,
        STRING_AGG(PTA.TagName_Cleaned, '><' ORDER BY PTA.TagName_Cleaned) AS PostTagsDelimited,
        EXTRACT(EPOCH FROM (NOW() - PDA.PostCreationDate)) / (24 * 3600.0) AS PostAgeInDays,
        -- Custom complex impact score incorporating various metrics and history details
        (PDA.Score * 0.75 + PDA.ViewCount * 0.05 + COALESCE(PDA.PostFavoriteCount, 0) * 2.0 + PDA.ActualCommentsCount * 0.5 + PDA.AnswerCount * 1.5) *
        (1 + (COALESCE(PHT.ContentEditCount, 0) * 0.05) - (CASE WHEN PHT.HoursToFirstEdit IS NULL OR PHT.HoursToFirstEdit > 24 THEN 0.1 ELSE 0 END)) *
        (CASE WHEN PDA.EffectiveClosedDate IS NOT NULL THEN 0.5 ELSE 1.0 END) AS AdvancedImpactScore
    FROM UserProfileSummary AS UPS
    INNER JOIN PostDetailAggregates AS PDA ON UPS.UserId = PDA.OwnerUserId
    LEFT JOIN PostHistoryTimeline AS PHT ON PDA.PostId = PHT.PostId
    LEFT JOIN PostTaggingAnalysis AS PTA ON PDA.PostId = PTA.PostId
    GROUP BY
        UPS.UserId, UPS.DisplayName, UPS.UserLocation, UPS.Reputation, UPS.GlobalReputationRank,
        PDA.PostId, PDA.PostTypeName, PDA.Title, PDA.PostCreationDate, PDA.Score, PDA.ViewCount, PDA.AnswerCount,
        PDA.ActualCommentsCount, PDA.PostFavoriteCount, PDA.TotalRelatedLinks, PDA.TotalDuplicateLinks,
        PDA.LatestCommentContent, PDA.WasPostMigrated, PDA.EffectiveClosedDate, PDA.PostFullBody, PDA.ParentId, PDA.LastActivityDate,
        PHT.TotalHistoryEvents, PHT.UniqueEditorsCount, PHT.LatestHistoryEventDate, PHT.ContentEditCount, PHT.HoursToFirstEdit, PHT.LastContentEditorUserId
)
SELECT
    CPA.UserId,
    CPA.DisplayName,
    CPA.UserLocation,
    CPA.Reputation,
    CPA.GlobalReputationRank,
    CPA.PostId,
    CPA.PostTypeName,
    CPA.Title,
    CPA.PostCreationDate,
    CPA.Score,
    CPA.ViewCount,
    CPA.AnswerCount,
    CPA.AdvancedImpactScore,
    CPA.PostAgeInDays,
    CPA.LatestCommentContent,
    -- String expression: first 120 characters of post body, trimmed, reversed, or default string
    REVERSE(TRIM(COALESCE(SUBSTRING(CPA.PostFullBody, 1, 120), 'No Content Available For This Post'))) AS ReversedBodyExcerpt,
    -- NULL logic: display 'No Tags Provided' if PostTagsDelimited is NULL or empty
    COALESCE(NULLIF(CPA.PostTagsDelimited, ''), 'No Tags Provided') AS FormattedPostTags,
    -- Window function: Calculate average score for user's posts within a 6-month rolling window
    AVG(CPA.Score) OVER (PARTITION BY CPA.UserId ORDER BY CPA.PostCreationDate RANGE BETWEEN INTERVAL '6 month' PRECEDING AND CURRENT ROW) AS UserRollingAvgScore6Months,
    -- Window function: Rank posts by AdvancedImpactScore within their PostType, higher for more impact
    RANK() OVER (PARTITION BY CPA.PostTypeName ORDER BY CPA.AdvancedImpactScore DESC) AS PostTypeImpactRank,
    -- Window function: NTILE to categorize posts into 5 performance groups based on combined score and views for their type
    NTILE(5) OVER (PARTITION BY CPA.PostTypeName ORDER BY CPA.Score DESC, CPA.ViewCount DESC) AS PerformanceQuintile,
    -- Correlated subquery: Average reputation of users who commented on this specific post
    (
        SELECT AVG(U_Commenter.Reputation)
        FROM Comments AS Comm_sub
        INNER JOIN Users AS U_Commenter ON Comm_sub.UserId = U_Commenter.Id
        WHERE Comm_sub.PostId = CPA.PostId AND Comm_sub.UserId IS NOT NULL
    ) AS AvgCommenterReputation,
    -- Correlated subquery: Check if any gold badge for a tag associated with the post exists for the owner
    EXISTS (
        SELECT 1
        FROM Badges AS B_TagGold
        INNER JOIN PostTaggingAnalysis AS PTA_sub ON B_TagGold.Name = PTA_sub.TagName_Cleaned
        WHERE B_TagGold.UserId = CPA.UserId
          AND B_TagGold.Class = 1
          AND B_TagGold.TagBased = TRUE
          AND PTA_sub.PostId = CPA.PostId
    ) AS OwnerHasRelatedGoldTagBadge,
    -- Complicated Post Categorization using CASE, subqueries, and PERCENTILE_CONT
    CASE
        WHEN CPA.EffectiveClosedDate IS NOT NULL AND CPA.PostTypeName = 'Question' THEN 'Closed Question'
        WHEN CPA.PostTypeName = 'Answer' AND CPA.ParentId IS NOT NULL AND (SELECT P_Parent.ClosedDate FROM Posts AS P_Parent WHERE P_Parent.Id = CPA.ParentId) IS NOT NULL THEN 'Answer to Closed Q'
        WHEN CPA.PostTypeName = 'Question' AND COALESCE(CPA.AnswerCount, 0) = 0 AND CPA.PostAgeInDays > 60 THEN 'Stale Unanswered Q'
        WHEN CPA.AdvancedImpactScore >= (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY AdvancedImpactScore) FROM CombinedPostAndUserAnalytics) THEN 'Top 5% Impact Post'
        WHEN CPA.TotalDuplicateLinks > 0 AND CPA.PostTypeName = 'Question' THEN 'Potential Duplicate Q'
        ELSE 'General Active Post'
    END AS DetailedPostCategory,
    -- Set operator: Find tags common between this post and the top 100 most frequent tags globally (INTERSECT)
    (
        SELECT STRING_AGG(T_Common.TagName, ',')
        FROM Tags AS T_Common
        WHERE T_Common.Count >= 10000 -- Global popularity threshold
        INTERSECT
        SELECT PTA_main.TagName_Cleaned
        FROM PostTaggingAnalysis AS PTA_main
        WHERE PTA_main.PostId = CPA.PostId
    ) AS IntersectingTopPopularTags
FROM CombinedPostAndUserAnalytics AS CPA
WHERE
    CPA.PostCreationDate >= (NOW() - INTERVAL '2 years') -- Focus on recent activity
    AND CPA.Reputation >= 5000 -- Only highly reputed users
    AND CPA.AdvancedImpactScore > 150 -- Filter for impactful posts
    AND CPA.PostAgeInDays < 365 -- Posts from within the last year
    AND (
        (CPA.PostTypeName = 'Question' AND CPA.AnswerCount >= 1 AND CPA.Score > 10 AND CPA.TotalRelatedLinks > 0)
        OR
        (CPA.PostTypeName = 'Answer' AND CPA.Score > 20 AND CPA.ActualCommentsCount >= 3 AND CPA.LastContentEditorUserId IS NOT NULL)
        OR
        (CPA.PostTypeName IN ('Wiki', 'TagWiki') AND CPA.ContentEditCount >= 5 AND CPA.PostAgeInDays > 30)
    )
ORDER BY
    CPA.GlobalReputationRank ASC,
    CPA.AdvancedImpactScore DESC,
    CPA.PostLastActivityDate DESC,
    CPA.PostId ASC
LIMIT 10000;
