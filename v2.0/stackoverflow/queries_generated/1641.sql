-- {"query": "1641.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2676} 

WITH UserEngagementSummary AS (
    -- Aggregates user activity, including calculated reputation metrics and badge counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unspecified') AS UserLocation, -- NULL logic: Provide default for NULL Location
        u.Views AS UserProfileViews,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        -- Window function: Average reputation of users created in the same year.
        AVG(u.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AvgRepForYearCohort,
        -- Correlated subquery: Check for a specific "Gold" tag-based badge.
        EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.TagBased = TRUE) AS HasGoldTagBadge,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount, -- Complex predicate with FILTER clause
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views
),
PostContentAnalysis AS (
    -- Detailed analysis of posts, including edit history, tags, and acceptance status.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        -- String expression: Extract keywords from tags, handling potential NULL tags.
        REPLACE(REPLACE(COALESCE(p.Tags, ''), '><', ' '), '<', ''), '>', '' AS CleanedTagsString,
        -- Correlated subquery: Get the text of the initial body.
        (SELECT ph.Text FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 2 ORDER BY ph.CreationDate LIMIT 1) AS InitialPostBody,
        -- Count of significant edits (title, body, tags).
        COUNT(ph_edit.Id) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS SignificantEditCount,
        -- Window function: Rank posts by activity within each PostTypeId.
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC, p.Score DESC) AS ActivityRank,
        -- Window function: Calculate the time difference (in hours) from previous post of the same owner.
        EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 3600.0 AS TimeSincePrevPostHours,
        -- NULL logic and outer join: Default editor display name if not found.
        COALESCE(le.DisplayName, p.LastEditorDisplayName, 'Community') AS LastEditorDisplayName
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId
    LEFT JOIN Users le ON p.LastEditorUserId = le.Id -- Outer join for LastEditor
    GROUP BY p.Id, p.PostTypeId, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
             p.FavoriteCount, p.ClosedDate, p.OwnerUserId, p.AcceptedAnswerId, p.Tags, le.DisplayName, p.LastEditorDisplayName
),
PostClosureAndLinkData AS (
    -- Analyzes post closure history and linked/duplicate posts.
    SELECT
        ph_close.PostId,
        SUM(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN ph_close.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        -- Correlated subquery to get the latest close reason name, handling cases where Comment might not be a valid integer.
        (
            SELECT crt.Name
            FROM PostHistory ph_inner
            JOIN CloseReasonTypes crt ON crt.Id = CASE
                                                    WHEN ph_inner.Comment ~ '^[0-9]+$' THEN CAST(ph_inner.Comment AS SMALLINT)
                                                    ELSE NULL
                                                  END
            WHERE ph_inner.PostId = ph_close.PostId
            AND ph_inner.PostHistoryTypeId = 10
            AND ph_inner.Comment IS NOT NULL
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReasonName,
        MAX(ph_close.CreationDate) FILTER (WHERE ph_close.PostHistoryTypeId = 10) AS LastClosedDate,
        COUNT(DISTINCT pl.Id) AS TotalLinksToPost,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicates
    FROM PostHistory ph_close
    LEFT JOIN PostLinks pl ON ph_close.PostId = pl.PostId
    WHERE ph_close.PostHistoryTypeId IN (10, 11) -- Post Closed, Post Reopened
    GROUP BY ph_close.PostId
),
HotControversialPosts AS (
    -- Identifies posts that are both popular and have significant history using UNION ALL.
    SELECT
        pca.PostId,
        'Hot & Controversial' AS Category
    FROM PostContentAnalysis pca
    WHERE pca.ViewCount > 10000
    AND pca.FavoriteCount > 100
    AND pca.SignificantEditCount > 5
    UNION ALL
    SELECT
        pca.PostId,
        'Highly Commented, Few Answers' AS Category
    FROM PostContentAnalysis pca
    WHERE pca.CommentCount > 50
    AND (pca.AnswerCount < 3 OR pca.AnswerCount IS NULL) -- NULL logic for AnswerCount
    AND pca.PostTypeId = 1 -- Only questions
),
InactiveButHighImpactPosts AS (
    -- Finds posts that haven't been active recently but have high scores, using EXCEPT.
    SELECT
        pca.PostId,
        'Inactive High Score' AS Category
    FROM PostContentAnalysis pca
    WHERE pca.LastActivityDate < NOW() - INTERVAL '1 year'
    AND pca.Score > 50
    EXCEPT
    SELECT
        pca.PostId,
        'Inactive High Score' AS Category
    FROM PostContentAnalysis pca
    JOIN PostClosureAndLinkData pcld ON pca.PostId = pcld.PostId
    WHERE pcld.LastClosedDate IS NOT NULL
    AND pcld.LastClosedDate > NOW() - INTERVAL '6 months' -- Posts closed recently are not 'inactive' in this context
)
-- Main complex query to analyze users interacting with specific types of posts
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.UserLocation,
    ues.AvgRepForYearCohort,
    ues.HasGoldTagBadge,
    ues.GoldBadgesCount,
    pca.PostId,
    pca.Title,
    pca.PostCreationDate,
    pca.Score AS PostScore,
    pca.ViewCount AS PostViewCount,
    pca.SignificantEditCount,
    pca.CleanedTagsString,
    pca.LastEditorDisplayName,
    COALESCE(pcld.TotalCloseEvents, 0) AS TotalCloseEvents, -- NULL logic: default to 0 if no close data
    COALESCE(pcld.TotalReopenEvents, 0) AS TotalReopenEvents, -- NULL logic: default to 0 if no reopen data
    pcld.LatestCloseReasonName,
    hc.Category AS HotControversialCategory,
    ihip.Category AS InactiveHighImpactCategory,
    -- Complicated calculation: Ratio of score to views, considering nulls and division by zero.
    CAST(pca.Score AS NUMERIC) / NULLIF(pca.ViewCount, 0) AS ScoreToViewRatio,
    -- Complicated predicate/expression: Conditional string manipulation based on post status.
    CASE
        WHEN pca.ClosedDate IS NOT NULL AND COALESCE(pcld.TotalReopenEvents, 0) = 0 THEN 'ClosedPermanently'
        WHEN pca.AcceptedAnswerId IS NOT NULL THEN 'AnsweredWithAccept'
        WHEN pca.PostTypeId = 1 AND COALESCE(pca.AnswerCount, 0) = 0 AND COALESCE(pca.CommentCount, 0) > 5 THEN 'QuestionWithManyCommentsNoAnswers'
        ELSE 'OtherActivePost'
    END AS PostLifecycleStatus,
    -- String expression: Extract first 50 chars of initial body, if exists, handling potential NULL.
    SUBSTRING(COALESCE(pca.InitialPostBody, 'No initial body text.'), 1, 50) || CASE WHEN LENGTH(COALESCE(pca.InitialPostBody, '')) > 50 THEN '...' ELSE '' END AS InitialBodyExcerpt,
    -- Window function: Rank users by reputation within their location.
    RANK() OVER (PARTITION BY ues.UserLocation ORDER BY ues.Reputation DESC, ues.LastAccessDate DESC) AS RankByLocationReputation
FROM UserEngagementSummary ues
INNER JOIN PostContentAnalysis pca ON ues.UserId = pca.OwnerUserId
LEFT JOIN PostClosureAndLinkData pcld ON pca.PostId = pcld.PostId
LEFT JOIN HotControversialPosts hc ON pca.PostId = hc.PostId
LEFT JOIN InactiveButHighImpactPosts ihip ON pca.PostId = ihip.PostId
WHERE
    ues.Reputation > 10000 -- High reputation users
    AND pca.PostTypeId = 1 -- Only questions
    AND pca.SignificantEditCount >= 3 -- Posts with meaningful edits
    AND (pca.FavoriteCount > 50 OR ues.HasGoldTagBadge) -- Interesting posts or users with specific badges
    AND pca.PostCreationDate BETWEEN '2019-01-01' AND '2023-12-31' -- Date range for posts
    AND (
        -- Complicated predicate with NULL logic and string matching
        (COALESCE(pcld.TotalCloseEvents, 0) > 0 AND COALESCE(pcld.TotalReopenEvents, 0) > 0 AND COALESCE(pcld.LatestCloseReasonName, '') NOT ILIKE '%Duplicate%')
        OR
        (pca.CleanedTagsString ILIKE '%performance%' AND pca.Score > 20)
        OR
        (pca.TimeSincePrevPostHours IS NOT NULL AND pca.TimeSincePrevPostHours < 24 AND pca.ActivityRank <= 10) -- User posted frequently and recently ranked high
    )
ORDER BY
    ues.Reputation DESC,
    pca.PostCreationDate DESC,
    pca.Score DESC
LIMIT 200;
