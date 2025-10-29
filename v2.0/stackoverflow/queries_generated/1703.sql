-- {"query": "1703.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3276} 

WITH UserPostTagStats AS (
    -- Aggregate post-related statistics for users involved with 'sql' or 'performance' tags.
    -- This CTE processes raw tag strings, extracting individual tags and filtering for relevance.
    SELECT
        p.OwnerUserId AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        MAX(p.LastActivityDate) AS LastPostActivity,
        -- Use CROSS JOIN LATERAL UNNEST with STRING_TO_ARRAY to parse the tags string into individual tags.
        -- This allows for robust filtering and counting of distinct relevant tags per user.
        COUNT(DISTINCT t.tag_value) AS DistinctRelevantTags,
        MAX(CASE WHEN LOWER(p.Tags) LIKE '%<sql>%' THEN 1 ELSE 0 END) AS HasSqlPosts,
        MAX(CASE WHEN LOWER(p.Tags) LIKE '%<performance>%' THEN 1 ELSE 0 END) AS HasPerformancePosts
    FROM Posts AS p
    INNER JOIN Users AS u ON p.OwnerUserId = u.Id
    -- Lateral join to unnest tags. Assumes tags are in format <tag1><tag2>...
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t(tag_value)
    WHERE
        p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
        AND p.OwnerUserId IS NOT NULL
        AND LOWER(t.tag_value) IN ('sql', 'performance') -- Filter for posts related to these specific tags
    GROUP BY p.OwnerUserId, u.DisplayName, u.Reputation, u.CreationDate
),
UserEditAndCommentActivity AS (
    -- Summarize user edit and comment activity.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEdits, -- Post edits
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS TotalCloseDeleteVotes, -- Close/Delete votes
        MAX(ph.CreationDate) AS LastEditDate,
        -- Correlated subquery to count comments made by the user
        (
            SELECT COUNT(c.Id)
            FROM Comments AS c
            WHERE c.UserId = ph.UserId
        ) AS TotalCommentsMade
    FROM PostHistory AS ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserBadgeVoteSummary AS (
    -- Aggregate badge and vote statistics for users.
    SELECT
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Scalar subquery for net votes received on their posts (UpMod minus DownMod)
        (
            SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0)
            FROM Votes AS v
            INNER JOIN Posts AS p ON v.PostId = p.Id
            WHERE p.OwnerUserId = u.Id AND v.VoteTypeId IN (2, 3)
        ) AS NetVotesReceivedOnPosts,
        -- Scalar subquery for net votes given by the user (UpMod minus DownMod)
        (
            SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0)
            FROM Votes AS v
            WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)
        ) AS NetVotesGiven
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id
),
CombinedUserPerformance AS (
    -- Combine all user-centric statistics from previous CTEs and calculate a RawEngagementScore.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ups.AveragePostScore, 0.0) AS AveragePostScore,
        COALESCE(ups.TotalPostViews, 0) AS TotalPostViews,
        COALESCE(ups.LastPostActivity, u.LastAccessDate) AS EffectiveLastActivity,
        COALESCE(ups.DistinctRelevantTags, 0) AS DistinctRelevantTags,
        COALESCE(ueca.TotalEdits, 0) AS TotalEdits,
        COALESCE(ueca.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.NetVotesReceivedOnPosts, 0) AS NetVotesReceivedOnPosts,
        COALESCE(ubs.NetVotesGiven, 0) AS NetVotesGiven,
        -- Complex calculation for RawEngagementScore, incorporating various metrics and recency.
        -- Uses AGE for time difference, COALESCE for NULL safety, and complex arithmetic operations.
        (
            (COALESCE(ups.AveragePostScore, 0.0) * COALESCE(ups.TotalPosts, 0.0) * 1000)
            + COALESCE(ups.TotalPostViews, 0)
            + (COALESCE(ueca.TotalEdits, 0) * 50)
            + (COALESCE(ueca.TotalCommentsMade, 0) * 10)
            + (COALESCE(ubs.GoldBadges, 0) * 500)
            + (COALESCE(ubs.SilverBadges, 0) * 200)
            + (COALESCE(ubs.BronzeBadges, 0) * 50)
            + (COALESCE(ubs.NetVotesReceivedOnPosts, 0) * 2)
        ) / (
            1 + EXTRACT(EPOCH FROM AGE(CURRENT_TIMESTAMP, COALESCE(ups.LastPostActivity, u.LastAccessDate))) / (60 * 60 * 24 * 30.0) -- Factor in activity recency (months)
        ) AS RawEngagementScore,
        COALESCE(ups.HasSqlPosts, 0) AS HasSqlPosts,
        COALESCE(ups.HasPerformancePosts, 0) AS HasPerformancePosts
    FROM Users AS u
    LEFT JOIN UserPostTagStats AS ups ON u.Id = ups.UserId
    LEFT JOIN UserEditAndCommentActivity AS ueca ON u.Id = ueca.UserId
    LEFT JOIN UserBadgeVoteSummary AS ubs ON u.Id = ubs.UserId
    WHERE
        u.Reputation > 100 -- Filter out users with very low reputation
        AND (COALESCE(ups.HasSqlPosts, 0) = 1 OR COALESCE(ups.HasPerformancePosts, 0) = 1) -- Only include users with relevant posts
),
RankedAndCategorizedUsers AS (
    -- Apply various window functions for global and partitioned ranking, and peer comparison.
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalPostScore,
        AveragePostScore,
        TotalPostViews,
        EffectiveLastActivity,
        DistinctRelevantTags,
        TotalEdits,
        TotalCommentsMade,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        NetVotesReceivedOnPosts,
        NetVotesGiven,
        RawEngagementScore,
        HasSqlPosts,
        HasPerformancePosts,
        -- Rank users by their engagement score globally
        RANK() OVER (ORDER BY RawEngagementScore DESC, Reputation DESC) AS GlobalEngagementRank,
        -- NTILE to categorize users into 5 reputation groups for peer analysis
        NTILE(5) OVER (ORDER BY Reputation DESC) AS ReputationQuintile,
        -- Rank users within their calculated reputation quintile by engagement score
        RANK() OVER (PARTITION BY NTILE(5) OVER (ORDER BY Reputation DESC) ORDER BY RawEngagementScore DESC) AS QuintileEngagementRank,
        -- Use LAG to compare current user's engagement with the previous one in the global ranking
        LAG(RawEngagementScore, 1, 0.0) OVER (ORDER BY RawEngagementScore DESC) AS PreviousEngagementScore,
        -- Calculate the average engagement score within their reputation quintile
        AVG(RawEngagementScore) OVER (PARTITION BY NTILE(5) OVER (ORDER BY Reputation DESC)) AS AvgEngagementInQuintile
    FROM CombinedUserPerformance
    WHERE RawEngagementScore IS NOT NULL AND RawEngagementScore > 0 -- Exclude users with invalid/zero engagement scores
),
FinalUserFocusSelection AS (
    -- Use UNION ALL to combine users into distinct sets based on their primary focus (SQL, Performance, or Both).
    -- This allows for separate filtering and then combining the results.
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'SQL' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasSqlPosts = 1 AND HasPerformancePosts = 0
    AND QuintileEngagementRank <= 10 -- Select top 10 users in their quintile for SQL focus

    UNION ALL

    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'Performance' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasPerformancePosts = 1 AND HasSqlPosts = 0
    AND QuintileEngagementRank <= 10 -- Select top 10 users in their quintile for Performance focus

    UNION ALL

    SELECT
        UserId,
        DisplayName,
        Reputation,
        GlobalEngagementRank,
        QuintileEngagementRank,
        RawEngagementScore,
        'Both' AS FocusArea,
        HasSqlPosts,
        HasPerformancePosts
    FROM RankedAndCategorizedUsers
    WHERE HasSqlPosts = 1 AND HasPerformancePosts = 1
    AND QuintileEngagementRank <= 5 -- Select top 5 users in their quintile for both focus areas
)
-- Final selection: Consolidate user data, apply further filtering, and include complex output expressions.
SELECT DISTINCT ON (fu.UserId) -- PostgreSQL-specific: Ensures each user appears only once based on priority of FocusArea
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.FocusArea,
    -- Demonstrate string expressions and complex NULL logic with CASE statements for user labeling
    CASE
        WHEN fu.FocusArea = 'Both' THEN 'Omni-Contributor'
        WHEN fu.FocusArea = 'SQL' THEN CONCAT('SQL Master (Rank: ', fu.QuintileEngagementRank, ')')
        WHEN fu.FocusArea = 'Performance' THEN CONCAT('Perf Guru (Rank: ', fu.QuintileEngagementRank, ')')
        ELSE 'Unknown Niche' -- Should not happen with current filters
    END AS UserLabel,
    fu.GlobalEngagementRank,
    fu.ReputationQuintile,
    fu.QuintileEngagementRank,
    fu.RawEngagementScore,
    r.TotalPosts,
    r.AveragePostScore,
    r.TotalEdits,
    r.GoldBadges,
    r.NetVotesReceivedOnPosts,
    -- Another complex expression for AdjustedImpactScore, using NULLIF to prevent division by zero
    NULLIF(
        ROUND(
            (r.NetVotesReceivedOnPosts::NUMERIC / NULLIF(r.TotalPosts, 0) + r.AveragePostScore) *
            (1 + (r.GoldBadges + r.SilverBadges) * 0.1) -- Boost for badge holders
        , 2), 0
    ) AS AdjustedImpactScore,
    r.PreviousEngagementScore,
    r.AvgEngagementInQuintile,
    -- Correlated subquery to fetch the title of one of their top-scored questions in their primary focus area.
    (
        SELECT p.Title
        FROM Posts AS p
        WHERE p.OwnerUserId = fu.UserId
          AND p.PostTypeId = 1 -- Only questions
          AND p.Tags ILIKE '%<' || LOWER(fu.FocusArea) || '>%' -- Case-insensitive tag matching
        ORDER BY p.Score DESC, p.CreationDate DESC
        LIMIT 1
    ) AS TopPostTitleInFocus
FROM FinalUserFocusSelection AS fu
INNER JOIN RankedAndCategorizedUsers AS r ON fu.UserId = r.UserId -- Join back to get full ranked data
WHERE
    fu.GlobalEngagementRank <= 150 -- Limit the global set of users considered
    AND fu.ReputationQuintile IN (1, 2) -- Further narrow down to users in top 2 reputation quintiles
ORDER BY fu.UserId,
         -- Define priority for DISTINCT ON: 'Both' > 'SQL' > 'Performance'
         CASE WHEN fu.FocusArea = 'Both' THEN 1
              WHEN fu.FocusArea = 'SQL' THEN 2
              WHEN fu.FocusArea = 'Performance' THEN 3
              ELSE 4 END
LIMIT 50; -- Final output limited to 50 results for benchmarking purposes
