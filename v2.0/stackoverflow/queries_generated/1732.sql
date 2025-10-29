-- {"query": "1732.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3695} 

WITH UserPostStats AS (
    -- CTE 1: Aggregates basic post statistics for each user
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreByOwner,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScoreByOwner,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViewsByOwner,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountByOwner
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL -- Exclude posts owned by community user (-1) or deleted users
    GROUP BY p.OwnerUserId
),
PostDetailsExtended AS (
    -- CTE 2: Enriches post data with correlated subqueries, string parsing, and complex calculations
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS DirectCommentCount,
        p.AcceptedAnswerId,
        p.ParentId,
        -- String expression: Extracts the first tag from the 'Tags' string, or assigns 'untagged' if none
        COALESCE(
            NULLIF(TRIM(SUBSTRING(p.Tags, 2, CASE WHEN POSITION('><' IN p.Tags) > 0 THEN POSITION('><' IN p.Tags) - 2 ELSE LENGTH(p.Tags) - 2 END)), ''),
            'untagged'
        ) AS PrimaryTag,
        COALESCE(p.Title, '[Untitled Post]') AS PostTitle, -- NULL logic for post titles
        p.ClosedDate,
        -- Correlated Subquery 1: Calculates the total number of UpMod (2) and DownMod (3) votes from the Votes table for a post
        (SELECT SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id) AS TotalVotesFromTable,
        -- Correlated Subquery 2: Checks if a post has ever been subjected to migration (PostHistoryTypeIds 17, 35, 36)
        EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (17, 35, 36)) AS WasMigrated,
        -- Complex calculation: Ratio of total votes to view count, handling potential division by zero
        CASE
            WHEN p.ViewCount > 0 THEN CAST((SELECT COUNT(v_inner.Id) FROM Votes v_inner WHERE v_inner.PostId = p.Id AND v_inner.VoteTypeId IN (2,3)) AS NUMERIC) / p.ViewCount
            ELSE 0.0
        END AS VoteToViewRatio,
        -- NULL logic: Calculates days since the post's last activity, defaulting to creation date if no activity
        EXTRACT(DAY FROM (NOW() - COALESCE(p.LastActivityDate, p.CreationDate))) AS DaysSinceLastActivity,
        -- Correlated Subquery 3: Counts distinct users who have edited the post (PostHistoryTypeIds 4, 5, 6 for title/body/tags edits)
        (SELECT COUNT(DISTINCT ph_editors.UserId) FROM PostHistory ph_editors WHERE ph_editors.PostId = p.Id AND ph_editors.PostHistoryTypeId IN (4, 5, 6)) AS DistinctEditorCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
),
PostEngagementSummary AS (
    -- CTE 3: Aggregates post-level engagement (comments, edit/close/reopen history) and applies a window function
    SELECT
        pde.PostId,
        pde.PostTypeId,
        pde.OwnerUserId,
        pde.PrimaryTag,
        pde.PostScore,
        pde.PostTitle,
        pde.TotalVotesFromTable,
        pde.VoteToViewRatio,
        pde.DaysSinceLastActivity,
        pde.DistinctEditorCount,
        pde.WasMigrated,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnPost,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreOnPost,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        -- Window function: Ranks posts by score within their respective primary tag
        RANK() OVER (PARTITION BY pde.PrimaryTag ORDER BY pde.PostScore DESC, pde.PostCreationDate DESC) AS PostRankInTag
    FROM PostDetailsExtended pde
    LEFT JOIN Comments c ON pde.PostId = c.PostId
    LEFT JOIN PostHistory ph ON pde.PostId = ph.PostId
    GROUP BY
        pde.PostId, pde.PostTypeId, pde.OwnerUserId, pde.PrimaryTag, pde.PostScore, pde.PostTitle,
        pde.TotalVotesFromTable, pde.VoteToViewRatio, pde.DaysSinceLastActivity, pde.DistinctEditorCount, pde.WasMigrated
),
UserOverallMetrics AS (
    -- CTE 4: Consolidates user-level information including reputation, badges, and aggregated post stats
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.UpVotes AS UpVotesGiven, -- Total upvotes given by the user
        u.DownVotes AS DownVotesGiven, -- Total downvotes given by the user
        ups.TotalPostsOwned,
        ups.QuestionsOwned,
        ups.AnswersOwned,
        ups.TotalPostScoreByOwner,
        ups.AvgPostScoreByOwner,
        ups.TotalPostViewsByOwner,
        ups.TotalFavoriteCountByOwner,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Complex calculation: Ratio of Gold/Silver badges to total badges, handling division by zero and NULL
        COALESCE(CAST(SUM(CASE WHEN b.Class IN (1, 2) THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(DISTINCT b.Id), 0), 0.0) AS HighClassBadgeRatio,
        -- Correlated subquery: Checks if the user has a specific 'Enthusiast' badge
        EXISTS (SELECT 1 FROM Badges b_inner WHERE b_inner.UserId = u.Id AND b_inner.Name = 'Enthusiast') AS HasEnthusiastBadge
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location,
        u.UpVotes, u.DownVotes, ups.TotalPostsOwned, ups.QuestionsOwned, ups.AnswersOwned,
        ups.TotalPostScoreByOwner, ups.AvgPostScoreByOwner, ups.TotalPostViewsByOwner, ups.TotalFavoriteCountByOwner
),
WeightedUserInfluence AS (
    -- CTE 5: Calculates a comprehensive influence score for each user based on various weighted metrics
    SELECT
        uom.UserId,
        uom.DisplayName,
        uom.Reputation,
        uom.TotalPostsOwned,
        uom.QuestionsOwned,
        uom.AnswersOwned,
        uom.TotalBadges,
        uom.GoldBadges,
        uom.HighClassBadgeRatio,
        uom.HasEnthusiastBadge,
        SUM(COALESCE(pes.PostScore, 0)) AS SumOfPostScores,
        SUM(COALESCE(pes.TotalCommentsOnPost, 0)) AS SumOfCommentsOnPosts,
        SUM(COALESCE(pes.TotalEditEvents, 0)) AS SumOfEditEvents,
        SUM(COALESCE(pes.TotalCloseEvents, 0)) AS SumOfCloseEvents,
        SUM(COALESCE(pes.TotalReopenEvents, 0)) AS SumOfReopenEvents,
        -- Elaborate influence score calculation using multiple weighted factors and NULL handling
        (
            (uom.Reputation * 0.4) +
            (COALESCE(uom.AvgPostScoreByOwner, 0.0) * 0.5) +
            (COALESCE(SUM(pes.TotalVotesFromTable), 0) * 0.05) +
            (COALESCE(SUM(pes.TotalCommentsOnPost), 0) * 0.02) +
            (COALESCE(SUM(pes.TotalEditEvents), 0) * 0.01) +
            (COALESCE(uom.HighClassBadgeRatio, 0.0) * 100) + -- Boost for higher-class badges
            (COALESCE(uom.TotalFavoriteCountByOwner, 0) * 0.03) +
            (COALESCE(CAST(uom.AnswersOwned AS NUMERIC) / NULLIF(uom.QuestionsOwned + uom.AnswersOwned, 0), 0.0) * 50) -- Weight for answer contribution ratio
        ) AS RawInfluenceScore,
        -- String expression: Concatenates a summary of user's badges (Gold, Silver, Bronze)
        'G:' || COALESCE(CAST(uom.GoldBadges AS VARCHAR), '0') ||
        ',S:' || COALESCE(CAST(uom.SilverBadges AS VARCHAR), '0') ||
        ',B:' || COALESCE(CAST(uom.BronzeBadges AS VARCHAR), '0') AS BadgeSummary
    FROM UserOverallMetrics uom
    LEFT JOIN PostEngagementSummary pes ON uom.UserId = pes.OwnerUserId
    GROUP BY
        uom.UserId, uom.DisplayName, uom.Reputation, uom.TotalPostsOwned, uom.QuestionsOwned, uom.AnswersOwned,
        uom.TotalBadges, uom.GoldBadges, uom.HighClassBadgeRatio, uom.HasEnthusiastBadge,
        uom.AvgPostScoreByOwner, uom.TotalFavoriteCountByOwner
),
TopTagsByInfluence AS (
    -- CTE 6: Identifies top tags based on aggregated post influence, using a window function for ranking
    SELECT
        PrimaryTag,
        COUNT(PostId) AS TaggedPostsCount,
        SUM(PostScore) AS TagTotalScore,
        AVG(VoteToViewRatio) AS TagAvgVoteToViewRatio,
        RANK() OVER (ORDER BY SUM(PostScore) DESC, COUNT(PostId) DESC) AS TagScoreRank
    FROM PostEngagementSummary
    WHERE PrimaryTag IS NOT NULL AND PrimaryTag != 'untagged'
    GROUP BY PrimaryTag
    HAVING COUNT(PostId) >= 10 -- Only consider tags with a minimum number of posts
),
NegativeImpactUsers AS (
    -- CTE 7: Example of Set Operators - Identifies users who exhibit primarily negative behavior patterns.
    -- Users who have given more than 50 downvotes
    SELECT DISTINCT v.UserId
    FROM Votes v
    WHERE v.VoteTypeId = 3 -- DownMod (downvote)
    GROUP BY v.UserId
    HAVING COUNT(*) > 50

    EXCEPT -- Set operator: Excludes users from the first set who are also present in the second set

    -- Users who have provided at least one accepted answer OR owned a gold badge
    SELECT DISTINCT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL
    UNION -- Set operator: Combines users from both subqueries
    SELECT DISTINCT b.UserId
    FROM Badges b
    WHERE b.Class = 1 -- Gold badge
)
-- Final Selection: Combines all insights, applies final rankings, and filters for high-impact users
SELECT
    wui.UserId,
    wui.DisplayName,
    wui.Reputation,
    wui.TotalPostsOwned,
    wui.QuestionsOwned,
    wui.AnswersOwned,
    wui.SumOfPostScores,
    wui.SumOfCommentsOnPosts,
    wui.SumOfEditEvents,
    wui.SumOfCloseEvents,
    wui.TotalBadges,
    wui.GoldBadges,
    wui.BadgeSummary,
    wui.RawInfluenceScore,
    -- Window function: Ranks users globally by their calculated influence score
    RANK() OVER (ORDER BY wui.RawInfluenceScore DESC, wui.Reputation DESC) AS OverallInfluenceRank,
    -- Window function: Calculates the user's reputation as a percentage of the maximum reputation within their geographical location
    COALESCE(CAST(wui.Reputation AS NUMERIC) / NULLIF(MAX(uom.Reputation) OVER (PARTITION BY uom.Location), 0), 0.0) AS RepPercentageInLocation,
    -- Window function: Calculates the average influence score of users who joined within a 30-day moving window around this user's join date
    AVG(wui.RawInfluenceScore) OVER (
        ORDER BY uom.UserCreationDate
        RANGE BETWEEN INTERVAL '15 days' PRECEDING AND INTERVAL '15 days' FOLLOWING
    ) AS AvgInfluenceScoreAroundJoinDate,
    -- Correlated Subquery: Identifies the single most influential tag (by post count and tag score rank) the user contributed to
    (
        SELECT ttb.PrimaryTag
        FROM PostEngagementSummary pes_inner
        JOIN TopTagsByInfluence ttb ON pes_inner.PrimaryTag = ttb.PrimaryTag
        WHERE pes_inner.OwnerUserId = wui.UserId
        GROUP BY ttb.PrimaryTag, ttb.TagScoreRank
        ORDER BY COUNT(pes_inner.PostId) DESC, ttb.TagScoreRank ASC
        LIMIT 1
    ) AS MostInfluentialTagContributed,
    -- Complicated predicate: Categorizes users based on their 'NegativeImpactUsers' status and reputation
    CASE
        WHEN wui.UserId IN (SELECT UserId FROM NegativeImpactUsers) AND wui.Reputation > 1000 THEN 'HighReputationNegative'
        WHEN wui.UserId IN (SELECT UserId FROM NegativeImpactUsers) THEN 'NegativeImpactUser'
        ELSE 'PositiveContributor'
    END AS UserContributionCategorization
FROM WeightedUserInfluence wui
INNER JOIN UserOverallMetrics uom ON wui.UserId = uom.UserId -- Joins to retrieve Location and UserCreationDate for window functions
WHERE
    wui.TotalPostsOwned > 0 -- Filters for users who own at least one post
    AND wui.Reputation > 100 -- Filters for users with a minimum reputation, implying some engagement
ORDER BY OverallInfluenceRank ASC, wui.Reputation DESC
LIMIT 100;
