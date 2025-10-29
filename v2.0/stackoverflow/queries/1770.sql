-- {"query": "1770.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3536} 
WITH UserEngagementSummary AS (
    -- Gathers comprehensive statistics and categorizes users based on their engagement and reputation.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUserUpVotesGiven,
        u.DownVotes AS TotalUserDownVotesGiven,
        COUNT(DISTINCT p_own.Id) AS TotalOwnedPosts,
        COUNT(DISTINCT p_edited.Id) AS TotalEditedPostsBySelf,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationQuintile, -- Divides users into 5 reputation tiers
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS UserAccountAgeYears, -- Calculates user account age in years
        COALESCE(u.Location, 'Unknown Location') AS UserLocationCategory, -- Handles NULL for Location
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p_own ON u.Id = p_own.OwnerUserId
    LEFT JOIN Posts p_edited ON u.Id = p_edited.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location
),
PostVersionHistory AS (
    -- Tracks post revisions, closing events, and calculates derived metrics for post content changes.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.LastEditDate,
        p.ClosedDate,
        p.Title,
        p.Tags,
        p.Body,
        pht.Name AS LatestHistoryTypeName, -- Name of the latest history event type
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorContentEdits, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS RollbackCount, -- Reverted edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEvents, -- Number of close events
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS LastContentEditTimestamp,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS FirstContentEditTimestamp,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))) / (60 * 60 * 24) AS DaysBetweenFirstAndLastEdit, -- Time span of edits
        -- Correlated subquery: Get the text of the *first* edit for body changes
        (SELECT ph_first.Text FROM PostHistory ph_first WHERE ph_first.PostId = p.Id AND ph_first.PostHistoryTypeId = 5 ORDER BY ph_first.CreationDate ASC LIMIT 1) AS InitialPostBodySnapshot,
        -- Non-correlated subquery: Get the average score of all comments for questions
        (SELECT AVG(CAST(c_sub.Score AS NUMERIC)) FROM Comments c_sub WHERE c_sub.PostId = p.Id AND c_sub.Score IS NOT NULL) AS AvgPostCommentScore,
        -- Complex date calculation for time since last activity
        EXTRACT(HOUR FROM (cast('2024-10-01 12:34:56' as timestamp) - p.LastActivityDate)) AS HoursSinceLastActivity
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
             p.FavoriteCount, p.OwnerUserId, p.LastEditorUserId, p.LastEditDate, p.ClosedDate,
             p.Title, p.Tags, p.Body, p.LastActivityDate, pht.Name
),
PostLinkAndTagAnalysis AS (
    -- Analyzes inter-post relationships (links) and extracts structured tag data.
    SELECT
        p.Id AS PostId,
        p.Tags,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinkedPosts, -- How many posts link to this one
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatePosts, -- How many posts are duplicates of this one
        MAX(pl.CreationDate) FILTER (WHERE pl.LinkTypeId = 3) AS LastDuplicateLinkDate,
        MIN(pl.CreationDate) FILTER (WHERE pl.LinkTypeId = 1) AS FirstLinkedDate,
        -- Extract the first tag (or 'untagged' if none/empty) using string functions and NULL logic
        COALESCE(
            NULLIF(TRIM(SUBSTRING(p.Tags FROM 2 FOR COALESCE(NULLIF(POSITION('><' IN p.Tags), 0), LENGTH(p.Tags) + 1) - 2)), ''),
            'untagged'
        ) AS PrimaryTag,
        (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')))/2 + 1 AS NumberOfTags, -- Counts the number of tags
        -- Categorizes posts based on specific tag presence (case-insensitive)
        CASE
            WHEN p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<database>%' OR p.Tags ILIKE '%<postgresql>%' OR p.Tags ILIKE '%<mysql>%' THEN 'Database'
            WHEN p.Tags ILIKE '%<performance>%' OR p.Tags ILIKE '%<optimization>%' THEN 'Performance'
            WHEN p.Tags ILIKE '%<java>%' OR p.Tags ILIKE '%<c#>%<' OR p.Tags ILIKE '%<python>%' THEN 'Programming Language'
            ELSE 'Other Tech'
        END AS TechnologyCategory,
        -- Window function: ranks posts by the number of linked posts within their technology category and creation year
        RANK() OVER (PARTITION BY (CASE
                                        WHEN p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<database>%' THEN 'Database'
                                        WHEN p.Tags ILIKE '%<performance>%' THEN 'Performance'
                                        ELSE 'Other Tech'
                                    END),
                                    EXTRACT(YEAR FROM p.CreationDate)
                     ORDER BY COUNT(pl.Id) DESC, p.Id) AS LinkedPostRankByTechYear
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.RelatedPostId -- Join for incoming links
    WHERE p.Tags IS NOT NULL
    GROUP BY p.Id, p.Tags, p.CreationDate
)
-- Main query: Joins all prepared CTEs and applies complex filters, calculations, and window functions.
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.ReputationQuintile,
    ues.UserAccountAgeYears,
    ues.TotalOwnedPosts,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,
    phv.PostId,
    phv.Title,
    pt.Name AS PostTypeName,
    phv.PostCreationDate,
    phv.Score AS CurrentPostScore,
    phv.ViewCount,
    phv.AnswerCount,
    phv.CommentCount,
    phv.FavoriteCount,
    phv.MajorContentEdits,
    phv.RollbackCount,
    phv.CloseEvents,
    phv.AvgPostCommentScore,
    phv.HoursSinceLastActivity,
    phv.InitialPostBodySnapshot,
    pla.PrimaryTag,
    pla.NumberOfTags,
    pla.TechnologyCategory,
    pla.TotalLinkedPosts,
    pla.TotalDuplicatePosts,
    pla.LastDuplicateLinkDate,
    -- Complex "Engagement Score" calculation, blending various post metrics and historical data.
    (
        phv.Score * 0.8 +
        (phv.ViewCount * 0.001) +
        (COALESCE(phv.AnswerCount, 0) * 1.5) +
        (COALESCE(phv.CommentCount, 0) * 0.7) +
        (COALESCE(phv.FavoriteCount, 0) * 2.5) +
        (phv.MajorContentEdits * 0.6) -
        (phv.CloseEvents * 10.0) - -- Significant penalty for closed posts
        (phv.RollbackCount * 3.0) +
        (COALESCE(phv.AvgPostCommentScore, 0) * 0.2) +
        (pla.TotalLinkedPosts * 1.0) -
        (pla.TotalDuplicatePosts * 5.0) -- Significant penalty for duplicates
    ) AS CalculatedEngagementScore,
    -- Determines post "Vitality" based on a mix of activity, edits, and age.
    CASE
        WHEN phv.ClosedDate IS NOT NULL THEN 'Dormant (Closed)'
        WHEN phv.HoursSinceLastActivity < 24 AND phv.MajorContentEdits > 0 THEN 'Highly Active'
        WHEN phv.HoursSinceLastActivity < 168 AND phv.CommentCount > 10 THEN 'Recently Engaged'
        WHEN phv.ViewCount > 5000 AND phv.PostCreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 'High Visibility Recent'
        ELSE 'Stable'
    END AS PostVitalityStatus,
    -- Example of an elaborate string expression: creating a masked user ID for privacy/tracking.
    'UID-' || LPAD(CAST(ues.UserId % 1000000 AS TEXT), 6, '0') || '-' || SUBSTRING(MD5(COALESCE(ues.DisplayName, 'unknown')), 1, 8) AS MaskedUserIdentifier,
    -- Conditional check if the post body or tags contain "advanced" database/performance keywords.
    (phv.Body ILIKE '%explain analyze%' OR phv.Body ILIKE '%execution plan%' OR pla.Tags ILIKE '%<indexing>%') AS HasAdvancedOptimizationKeywords,
    -- Window function: Average CalculatedEngagementScore for posts within the same TechnologyCategory for users in the same ReputationQuintile.
    AVG((
        phv.Score * 0.8 + (phv.ViewCount * 0.001) + (COALESCE(phv.AnswerCount, 0) * 1.5) +
        (COALESCE(phv.CommentCount, 0) * 0.7) + (COALESCE(phv.FavoriteCount, 0) * 2.5) +
        (phv.MajorContentEdits * 0.6) - (phv.CloseEvents * 10.0) -
        (phv.RollbackCount * 3.0) + (COALESCE(phv.AvgPostCommentScore, 0) * 0.2) +
        (pla.TotalLinkedPosts * 1.0) - (pla.TotalDuplicatePosts * 5.0)
    )) OVER (PARTITION BY ues.ReputationQuintile, pla.TechnologyCategory) AS AvgEngagementInGroup,
    -- Window function: Rank posts by Engagement Score within their PrimaryTag.
    RANK() OVER (PARTITION BY pla.PrimaryTag ORDER BY (
        phv.Score * 0.8 + (phv.ViewCount * 0.001) + (COALESCE(phv.AnswerCount, 0) * 1.5) +
        (COALESCE(phv.CommentCount, 0) * 0.7) + (COALESCE(phv.FavoriteCount, 0) * 2.5) +
        (phv.MajorContentEdits * 0.6) - (phv.CloseEvents * 10.0) -
        (phv.RollbackCount * 3.0) + (COALESCE(phv.AvgPostCommentScore, 0) * 0.2) +
        (pla.TotalLinkedPosts * 1.0) - (pla.TotalDuplicatePosts * 5.0)
    ) DESC) AS PostEngagementRankByPrimaryTag
FROM UserEngagementSummary ues
INNER JOIN PostVersionHistory phv ON ues.UserId = phv.OwnerUserId
LEFT JOIN PostLinkAndTagAnalysis pla ON phv.PostId = pla.PostId
LEFT JOIN PostTypes pt ON phv.PostTypeId = pt.Id
WHERE
    ues.Reputation > 20000 -- Focus on highly reputable users
    AND ues.TotalOwnedPosts >= 100 -- Users who have contributed a significant number of posts
    AND phv.PostTypeId = 1 -- Only questions are considered for this analysis
    AND phv.Score > 50 -- Only highly-rated questions
    AND phv.ViewCount > 10000 -- Questions with substantial visibility
    AND phv.MajorContentEdits >= 2 -- Questions that have been refined multiple times
    AND phv.RollbackCount = 0 -- Exclude posts with rollbacks (suggests content disputes)
    AND phv.ClosedDate IS NULL -- Only open questions
    AND pla.TechnologyCategory IN ('Database', 'Performance') -- Must be related to DB or Performance
    AND phv.PostCreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years' AND cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' -- Questions from a specific recent time window
    AND (phv.Body ILIKE '%transaction%' OR phv.Body ILIKE '%locking%' OR phv.Body ILIKE '%deadlock%') -- Body must contain critical keywords
    AND phv.HoursSinceLastActivity < 720 -- Last activity within the last month
ORDER BY
    CalculatedEngagementScore DESC,
    ues.Reputation DESC,
    phv.ViewCount DESC
LIMIT 1000;