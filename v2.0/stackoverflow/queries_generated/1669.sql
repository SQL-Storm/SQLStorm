-- {"query": "1669.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3006} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates user activity, reputation tiers, and core post metrics.
    -- Calculates total posts, answers, comments, average scores, and ranks users based on reputation and location.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsByOwner,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersByOwner,
        COUNT(c.Id) AS TotalCommentsByOwner,
        COALESCE(SUM(p.Score), 0) AS CumulativePostScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LatestPostCreationDate,
        -- Calculate days since user creation, handling potential NULL for LastAccessDate
        DATE_PART('day', COALESCE(u.LastAccessDate, u.CreationDate) - u.CreationDate) AS UserAccountAgeDays,
        NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankInLocationByReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.Location
    HAVING COUNT(DISTINCT p.Id) > 10 AND u.Reputation > 1500
),
PostVersionHistory AS (
    -- CTE 2: Analyzes post edit history, closure details, and linked duplicates.
    -- Uses window functions to compare post scores and aggregates various historical events.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score AS PostCurrentScore,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.ClosedDate,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueHistoryEventTypes,
        -- Aggregates distinct close reason names, filtering for PostHistoryTypeId 10
        STRING_AGG(DISTINCT crt.Name, ' | ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS CombinedCloseReasons,
        -- Aggregates IDs of duplicate posts, only if LinkTypeId is 3 (Duplicate)
        STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS VARCHAR), ',') FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinkedPostIds,
        -- Calculates duration between creation and last activity in hours, handling potential NULLs
        DATE_PART('hour', COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate) AS HoursToLastActivity,
        -- Compares current post score to the score of the previous post by the same owner
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        -- Counts specific edit types (title, body, tags)
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ExplicitEditCount,
        -- Calculates rolling average score for posts by the same owner over a 3-post window
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgOwnerPostScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND CAST(ph.Comment AS SMALLINT) = crt.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY p.Id, p.PostTypeId, p.Title, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.ClosedDate
    HAVING COUNT(ph.Id) > 5 AND p.PostCurrentScore > 0 -- Posts with significant history and positive score
),
TagPerformanceOverview AS (
    -- CTE 3: Analyzes performance metrics for specific tags.
    -- Uses string_to_array and UNNEST to extract individual tags, then aggregates their average scores and usage.
    SELECT
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(phv.Tags, 2, LENGTH(phv.Tags)-2), '><')))) AS TagName,
        COUNT(DISTINCT phv.PostId) AS PostsWithTagCount,
        AVG(phv.PostCurrentScore) AS AvgScoreForTag,
        MAX(phv.PostCreationDate) AS LatestTagUsageDate,
        MIN(phv.PostCreationDate) AS EarliestTagUsageDate,
        SUM(CASE WHEN phv.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsWithTag,
        SUM(CASE WHEN phv.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersWithTag,
        DENSE_RANK() OVER (ORDER BY AVG(phv.PostCurrentScore) DESC, COUNT(DISTINCT phv.PostId) DESC) AS TagPopularityRank
    FROM PostVersionHistory phv
    WHERE phv.Tags IS NOT NULL AND LENGTH(phv.Tags) > 2
    GROUP BY LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(phv.Tags, 2, LENGTH(phv.Tags)-2), '><'))))
    HAVING COUNT(DISTINCT phv.PostId) > 20 AND AVG(phv.PostCurrentScore) > 10
),
ModeratorInteractions AS (
    -- CTE 4: Identifies posts with direct moderator actions (lock/unlock, protect/unprotect, delete/undelete).
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        STRING_AGG(DISTINCT ph.Comment, '; ') FILTER (WHERE ph.Comment IS NOT NULL) AS ModeratorActionComments,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 END) AS TotalModeratorActionEvents,
        MAX(ph.CreationDate) AS LatestModeratorActionDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect
      AND ph.UserId IS NOT NULL -- Assuming moderator actions are linked to a user
    GROUP BY p.Id, p.Title, p.OwnerUserId
    HAVING COUNT(CASE WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN 1 END) >= 1 -- At least one specific moderator action
)
-- Main Query: Joins all CTEs and applies complex filtering, calculations, and conditional logic.
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalQuestionsByOwner,
    ues.TotalAnswersByOwner,
    phv.PostId,
    phv.Title,
    phv.PostCurrentScore,
    phv.ViewCount,
    phv.CombinedCloseReasons,
    phv.DuplicateLinkedPostIds,
    phv.TotalHistoryEntries,
    phv.HoursToLastActivity,
    phv.PreviousPostScoreByOwner,
    phv.ExplicitEditCount,
    phv.RollingAvgOwnerPostScore,
    tpo.TagName AS PrimaryConcernedTag,
    tpo.AvgScoreForTag,
    mi.TotalModeratorActionEvents,
    mi.ModeratorActionComments,
    -- Complex CASE expression for categorizing posts based on multiple criteria
    CASE
        WHEN phv.CombinedCloseReasons IS NOT NULL AND phv.DuplicateLinkedPostIds IS NOT NULL THEN 'Highly Intervened & Duplicated'
        WHEN phv.PostCurrentScore > ues.AvgAnswerScore * 2 AND phv.PostTypeId = 2 AND phv.ViewCount > 10000 THEN 'Exceptional Answer to Popular Question'
        WHEN phv.PostTypeId = 1 AND phv.ViewCount > 5000 AND phv.HoursToLastActivity < 48 AND phv.ExplicitEditCount = 0 THEN 'Viral Question with Minimal Edits'
        WHEN mi.TotalModeratorActionEvents > 0 THEN 'Moderator-Touched Post'
        ELSE 'Other Significant Activity Post'
    END AS PostImpactCategory,
    -- Elaborate calculation combining user and post metrics, handling potential division by zero and NULLs
    CAST(ues.Reputation AS NUMERIC) / NULLIF(ues.UserAccountAgeDays, 0) *
    COALESCE(phv.PostCurrentScore, 0) / NULLIF(phv.TotalHistoryEntries, 0) *
    (CASE WHEN tpo.AvgScoreForTag IS NOT NULL THEN tpo.AvgScoreForTag ELSE 1 END) AS WeightedUserPostInfluenceScore,
    -- String extraction for a potential email from 'AboutMe' using regex (example for PostgreSQL)
    SUBSTRING(u_orig.AboutMe FROM '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}') AS ExtractedEmailFromAboutMe,
    -- Length of the post title, COALESCE for NULL safety
    LENGTH(COALESCE(phv.Title, '')) AS PostTitleLength,
    -- Check if the post body contains a specific keyword (case-insensitive)
    (phv.PostId IN (SELECT Id FROM Posts WHERE Body ILIKE '%algorithm%' AND Body ILIKE '%performance%')) AS ContainsAlgorithmPerformanceKeywords
FROM UserEngagementSummary ues
INNER JOIN PostVersionHistory phv ON ues.UserId = phv.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join to find the most relevant (highest scoring) tag for each post
    SELECT
        tpo_inner.TagName,
        tpo_inner.AvgScoreForTag
    FROM TagPerformanceOverview tpo_inner
    WHERE phv.Tags ILIKE CONCAT('%<', tpo_inner.TagName, '>%' )
      AND (tpo_inner.TagName LIKE 'sql%' OR tpo_inner.TagName LIKE 'java%' OR tpo_inner.TagName LIKE 'python%')
    ORDER BY tpo_inner.AvgScoreForTag DESC, tpo_inner.PostsWithTagCount DESC
    LIMIT 1
) tpo ON TRUE
LEFT JOIN ModeratorInteractions mi ON phv.PostId = mi.PostId
INNER JOIN Users u_orig ON ues.UserId = u_orig.Id -- Join back to original Users table for full AboutMe access
WHERE ues.ReputationQuartile = 1 -- Filter for top 25% by reputation
  AND phv.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31'
  AND (phv.Title ILIKE '%benchmark%' OR phv.Title ILIKE '%optimization%' OR phv.Title ILIKE '%query performance%')
  AND phv.ViewCount > 2500
  AND (phv.PostId % 7 = 0 OR phv.OwnerUserId % 5 = 1) -- Arbitrary modulus filters for additional complexity
  AND NOT EXISTS ( -- Correlated subquery: exclude users who have 'Philosopher' badge
      SELECT 1 FROM Badges b WHERE b.UserId = ues.UserId AND b.Name = 'Philosopher' AND b.Class = 1
  )
  AND (phv.CombinedCloseReasons IS NULL OR phv.CombinedCloseReasons NOT ILIKE '%off-topic%') -- Exclude explicitly off-topic closed posts
ORDER BY WeightedUserPostInfluenceScore DESC, phv.PostCurrentScore DESC, phv.ViewCount DESC
LIMIT 200;
