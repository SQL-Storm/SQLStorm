-- {"query": "1048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4486} 

WITH UserActivityMetrics AS (
    -- CTE 1: Aggregate user activity and compute base metrics including rolling sums for activity trends
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views AS TotalProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreOwned,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViewCountOwned,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoriteCountOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScoreMade,
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotesReceived, -- From Posts
        COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS TotalDownVotesReceived, -- From Posts
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN ph.Id END) AS TotalEditsToOwnedPosts, -- All edit/rollback history types
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        COALESCE(
            (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.LastAccessDate)) / (3600 * 24))::numeric(10,2), -- Days since last access
            99999.00
        ) AS DaysSinceLastAccess,
        (u.UpVotes - u.DownVotes) AS NetVotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        -- Calculate average score of answers to questions owned by the user, using a correlated subquery
        COALESCE(
            (SELECT AVG(ap.Score)
             FROM Posts ap
             WHERE ap.PostTypeId = 2 -- Answers
               AND ap.ParentId IN (SELECT qp.Id FROM Posts qp WHERE qp.OwnerUserId = u.Id AND qp.PostTypeId = 1)),
            0
        ) AS AvgAnswerScoreForOwnedQuestions,
        -- Rolling sum of total post scores over a 7-day window ordered by LastAccessDate
        SUM(COALESCE(SUM(p.Score), 0)) OVER (ORDER BY u.LastAccessDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS Rolling7DayPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3) -- Votes *by* user on *any* post
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostId = p.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostTagAnalysis AS (
    -- CTE 2: Analyze tags and body content for specific keywords related to 'benchmarking' or 'performance'
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Body,
        p.Tags,
        p.CreationDate,
        CASE
            WHEN p.Tags IS NOT NULL AND (
                p.Tags LIKE '%<performance>%' OR
                p.Tags LIKE '%<optimization>%' OR
                p.Tags LIKE '%<benchmarking>%' OR
                p.Tags LIKE '%<speed>%' OR
                p.Tags LIKE '%<efficiency>%'
            ) THEN 1
            ELSE 0
        END AS HasPerformanceTag,
        CASE
            WHEN p.Body IS NOT NULL AND (
                POSITION('performance' IN LOWER(p.Body)) > 0 OR
                POSITION('optimize' IN LOWER(p.Body)) > 0 OR
                POSITION('benchmark' IN LOWER(p.Body)) > 0 OR
                POSITION('slow' IN LOWER(p.Body)) > 0 OR
                POSITION('fast' IN LOWER(p.Body)) > 0
            ) THEN 1
            ELSE 0
        END AS BodyMentionsPerformance,
        -- Calculate the number of distinct tags on a post (handling NULLs and potential empty strings)
        COALESCE(NULLIF(LENGTH(TRIM(p.Tags, '<>')) - LENGTH(REPLACE(TRIM(p.Tags, '<>'), '><', '')) + 1, 0), 0) AS NumTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
    AND p.OwnerUserId IS NOT NULL
),
AggregatedPerformancePosts AS (
    -- CTE 3: Aggregate performance-related post metrics per user
    SELECT
        pta.OwnerUserId AS UserId,
        COUNT(pta.PostId) FILTER (WHERE pta.HasPerformanceTag = 1) AS PerformanceTaggedPosts,
        COUNT(pta.PostId) FILTER (WHERE pta.BodyMentionsPerformance = 1) AS BodyMentionsPerformancePosts,
        COALESCE(AVG(pta.Score) FILTER (WHERE pta.HasPerformanceTag = 1), 0) AS AvgScorePerformancePosts,
        COALESCE(AVG(pta.ViewCount) FILTER (WHERE pta.HasPerformanceTag = 1), 0) AS AvgViewCountPerformancePosts,
        COALESCE(SUM(pta.NumTags), 0) AS TotalTagsUsedAcrossPosts
    FROM PostTagAnalysis pta
    GROUP BY pta.OwnerUserId
),
UserEngagementRanks AS (
    -- CTE 4: Combine user activity with performance post metrics and apply various window functions
    SELECT
        uam.UserId,
        uam.DisplayName,
        uam.Reputation,
        uam.CreationDate,
        uam.LastAccessDate,
        uam.TotalPostsOwned,
        uam.TotalPostScoreOwned,
        uam.TotalPostViewCountOwned,
        uam.TotalCommentsMade,
        uam.TotalEditsToOwnedPosts,
        uam.GoldBadges,
        uam.AvgAnswerScoreForOwnedQuestions,
        uam.DaysSinceLastAccess,
        uam.Rolling7DayPostScore,
        apr.PerformanceTaggedPosts,
        apr.BodyMentionsPerformancePosts,
        apr.AvgScorePerformancePosts,
        apr.AvgViewCountPerformancePosts,
        apr.TotalTagsUsedAcrossPosts,
        -- Window functions for ranking and distribution
        RANK() OVER (ORDER BY uam.Reputation DESC, uam.LastAccessDate DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY uam.TotalPostsOwned DESC) AS PostVolumeDecile,
        AVG(uam.TotalPostScoreOwned) OVER (PARTITION BY EXTRACT(YEAR FROM uam.CreationDate)) AS AvgUserPostScoreForCreationYear,
        -- Correlated subquery: Check if the user has an accepted answer to one of their own questions, and commented on it
        EXISTS (
            SELECT 1
            FROM Posts q_posts
            JOIN Posts a_posts ON q_posts.AcceptedAnswerId = a_posts.Id
            JOIN Comments ans_comment ON a_posts.Id = ans_comment.PostId
            WHERE q_posts.OwnerUserId = uam.UserId
              AND a_posts.OwnerUserId = uam.UserId
              AND ans_comment.UserId = uam.UserId
        ) AS HasSelfCommentedAcceptedAnswer
    FROM UserActivityMetrics uam
    LEFT JOIN AggregatedPerformancePosts apr ON uam.UserId = apr.UserId
    WHERE uam.Reputation > 500 -- Filter for more active/established users
      AND uam.TotalPostsOwned > 2
      AND uam.DaysSinceLastAccess < 180 -- Active within the last 6 months
),
UserInfluenceScore AS (
    -- CTE 5: Calculate a composite influence score based on various weighted metrics
    SELECT
        uer.UserId,
        uer.DisplayName,
        uer.Reputation,
        uer.CreationDate,
        uer.LastAccessDate,
        uer.TotalPostsOwned,
        uer.TotalPostScoreOwned,
        uer.TotalPostViewCountOwned,
        uer.TotalCommentsMade,
        uer.TotalEditsToOwnedPosts,
        uer.GoldBadges,
        uer.PerformanceTaggedPosts,
        uer.AvgAnswerScoreForOwnedQuestions,
        uer.HasSelfCommentedAcceptedAnswer,
        uer.ReputationRank,
        uer.PostVolumeDecile,
        uer.Rolling7DayPostScore,
        -- Elaborate influence score calculation with NULL handling and conditional weighting
        (
            (uer.Reputation * 0.15) +                                         -- 15% from Reputation
            (COALESCE(uer.TotalPostScoreOwned, 0) * 0.05) +                   -- 5% from total post score (handle NULL if no posts)
            (COALESCE(uer.TotalPostViewCountOwned, 0) * 0.001) +              -- A small fraction from total post views
            (COALESCE(uer.TotalCommentsMade, 0) * 0.02) +                     -- 2% from comments made
            (COALESCE(uer.TotalEditsToOwnedPosts, 0) * 0.03) +                -- 3% from edits
            (COALESCE(uer.GoldBadges, 0) * 10) +                              -- Bonus for Gold Badges
            (COALESCE(uer.PerformanceTaggedPosts, 0) * 5) +                   -- Bonus for performance related posts
            (COALESCE(uer.AvgAnswerScoreForOwnedQuestions, 0) * 0.05) +       -- Bonus for good answers to their questions
            (CASE WHEN uer.HasSelfCommentedAcceptedAnswer THEN 25 ELSE 0 END) + -- Significant bonus for self-commented accepted answers
            (CASE WHEN uer.DaysSinceLastAccess <= 30 THEN 50 ELSE 0 END) +    -- Recent activity bonus
            (COALESCE(uer.Rolling7DayPostScore, 0) * 0.005)                   -- Contribution from rolling sum
        )::numeric(15,2) AS InfluenceScore
    FROM UserEngagementRanks uer
    WHERE uer.ReputationRank <= 500 -- Consider top N users by reputation
),
TopInfluentialUsers AS (
    -- CTE 6: Final ranking based on the calculated influence score
    SELECT
        uis.UserId,
        uis.DisplayName,
        uis.Reputation,
        uis.CreationDate,
        uis.LastAccessDate,
        uis.TotalPostsOwned,
        uis.TotalCommentsMade,
        uis.GoldBadges,
        uis.InfluenceScore,
        RANK() OVER (ORDER BY uis.InfluenceScore DESC, uis.LastAccessDate DESC) AS GlobalInfluenceRank
    FROM UserInfluenceScore uis
    WHERE uis.InfluenceScore > 100 -- Minimum influence score to filter
),
RecentHighImpactPosts AS (
    -- CTE 7: Identify posts with high score and recent activity, possibly with multiple links or comments
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumLinkedPosts,
        COALESCE(
            (SELECT COUNT(DISTINCT cmt.Id)
             FROM Comments cmt
             WHERE cmt.PostId = p.Id AND cmt.Score > 5), -- Comments with high score
            0
        ) AS HighScoreCommentsCount,
        -- Extract the second tag from the Tags string, handling NULLs and various formats
        NULLIF(TRIM(SUBSTRING(p.Tags, POSITION('><' IN p.Tags) + 2, POSITION('>' IN SUBSTRING(p.Tags, POSITION('><' IN p.Tags) + 2)) - 1), '<>'), '') AS SecondTag
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts
    WHERE p.Score > 75
      AND p.LastActivityDate > CURRENT_DATE - INTERVAL '1 year'
      AND p.OwnerUserId IS NOT NULL
      AND p.PostTypeId = 1 -- Only questions for 'high-impact'
    GROUP BY p.Id, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.OwnerUserId, p.PostTypeId, p.Tags
),
UserPostLinkageSummary AS (
    -- CTE 8: Summarize how many high-impact posts a user is associated with and average score of those posts
    SELECT
        tui.UserId,
        COUNT(rhip.PostId) AS NumHighImpactPostsAssociated,
        AVG(rhip.Score) AS AvgHighImpactPostScore
    FROM TopInfluentialUsers tui
    JOIN RecentHighImpactPosts rhip ON tui.UserId = rhip.OwnerUserId
    GROUP BY tui.UserId
),
TopTagsByInfluencers AS (
    -- CTE 9: Find the most common tags among posts owned by top influential users
    SELECT
        LOWER(TRIM(unnested_tags.tag_name, '<>')) AS TagName,
        COUNT(DISTINCT p.Id) AS TaggedPostsByInfluencers,
        SUM(p.Score) AS TotalScoreForTag
    FROM TopInfluentialUsers tiu
    JOIN Posts p ON tiu.UserId = p.OwnerUserId
    CROSS JOIN LATERAL UNNEST(string_to_array(TRIM(p.Tags, '<>'), '><')) AS unnested_tags(tag_name)
    WHERE p.Tags IS NOT NULL
      AND LENGTH(TRIM(unnested_tags.tag_name, '<>')) > 0
    GROUP BY LOWER(TRIM(unnested_tags.tag_name, '<>'))
    HAVING COUNT(DISTINCT p.Id) > 5
)
-- Final SELECT statement combining all the insights, including set operations for "influential" and "tag-focused" users
SELECT
    tiu.UserId,
    tiu.DisplayName,
    tiu.Reputation,
    tiu.GlobalInfluenceRank,
    tiu.TotalPostsOwned,
    tiu.TotalCommentsMade,
    tiu.GoldBadges,
    tiu.InfluenceScore,
    upls.NumHighImpactPostsAssociated,
    upls.AvgHighImpactPostScore,
    -- Example of a complicated CASE expression with NULL logic and string concatenation
    COALESCE(
        CASE
            WHEN tiu.GoldBadges > 10 AND upls.NumHighImpactPostsAssociated > 5 AND tiu.Reputation > 150000 THEN 'Legendary Architect' || ' (Top ' || LPAD(tiu.GlobalInfluenceRank::text, 3, '0') || ')'
            WHEN tiu.GoldBadges > 3 AND upls.NumHighImpactPostsAssociated > 1 AND tiu.Reputation > 75000 THEN 'Veteran Trailblazer'
            WHEN tiu.TotalPostsOwned > 200 AND tiu.TotalCommentsMade > 500 AND upls.AvgHighImpactPostScore > 100 THEN 'Prodigious Contributor'
            ELSE 'Engaged Member'
        END,
        'Undetermined Role' -- Should rarely be hit given prior WHERE clauses, but demonstrates NULL handling
    ) AS UserTierClassification,
    -- Custom pseudonym using string functions
    UPPER(LEFT(COALESCE(tiu.DisplayName, 'Anon'), 4)) || '_' || LPAD(tiu.UserId::text, 6, '0') || '_' || UPPER(RIGHT(REPLACE(COALESCE(tiu.DisplayName, 'User'), ' ', ''), 3)) AS UserIdentifierHash,
    (SELECT MAX(t.TagName) FROM TopTagsByInfluencers t ORDER BY t.TaggedPostsByInfluencers DESC LIMIT 1) AS OverallMostPopularTagByInfluencers, -- Non-correlated subquery for a global statistic
    (SELECT AVG(Reputation) FROM TopInfluentialUsers WHERE GlobalInfluenceRank <= 10) AS AvgReputationOfTop10Influencers
FROM TopInfluentialUsers tiu
LEFT JOIN UserPostLinkageSummary upls ON tiu.UserId = upls.UserId
WHERE tiu.GlobalInfluenceRank <= 100
UNION ALL -- Combine with a separate query for users who are very active in a single tag, but might not be top overall
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    NULL AS GlobalInfluenceRank, -- Not ranked by overall influence
    COUNT(DISTINCT p.Id) AS TotalPostsOwned,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    0 AS InfluenceScore, -- Not calculated in this branch
    0 AS NumHighImpactPostsAssociated,
    0 AS AvgHighImpactPostScore,
    'Tag Specialist: ' || tt.TagName AS UserTierClassification,
    UPPER(LEFT(COALESCE(u.DisplayName, 'Anon'), 4)) || '_' || LPAD(u.Id::text, 6, '0') || '_' || UPPER(RIGHT(REPLACE(COALESCE(u.DisplayName, 'User'), ' ', ''), 3)) AS UserIdentifierHash,
    (SELECT MAX(t.TagName) FROM TopTagsByInfluencers t ORDER BY t.TaggedPostsByInfluencers DESC LIMIT 1) AS OverallMostPopularTagByInfluencers,
    (SELECT AVG(Reputation) FROM TopInfluentialUsers WHERE GlobalInfluenceRank <= 10) AS AvgReputationOfTop10Influencers
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
CROSS JOIN LATERAL UNNEST(string_to_array(TRIM(p.Tags, '<>'), '><')) AS unnested_tags(tag_name)
JOIN Comments c ON u.Id = c.UserId
JOIN Badges b ON u.Id = b.UserId
JOIN (SELECT TagName FROM TopTagsByInfluencers ORDER BY TaggedPostsByInfluencers DESC LIMIT 5) tt ON LOWER(TRIM(unnested_tags.tag_name, '<>')) = tt.TagName
WHERE u.Reputation > 2000
  AND u.TotalPostsOwned > 20
GROUP BY u.Id, u.DisplayName, u.Reputation, tt.TagName
HAVING COUNT(DISTINCT p.Id) FILTER (WHERE LOWER(TRIM(unnested_tags.tag_name, '<>')) = tt.TagName) > 10 -- At least 10 posts in that specific top tag
ORDER BY Reputation DESC, GlobalInfluenceRank ASC NULLS LAST;
