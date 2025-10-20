-- {"query": "49081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2315} 

WITH NormalizedTags AS (
    -- Pre-process 'Tags' column to extract individual tags and associate them with post metadata.
    -- This step is critical for efficiency when dealing with tag-based analysis.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
      AND length(p.Tags) > 2 -- Filter out posts with empty or malformed tags
      AND p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
      AND p.CreationDate >= NOW() - INTERVAL '2 years' -- Limit the initial scan to a recent period for tags
),
TagActivityWindow AS (
    -- Calculate recent (last 6 months) and previous (6-12 months ago) post counts per tag.
    -- Also calculates overall average score for quality assessment.
    SELECT
        nt.TagName,
        COUNT(DISTINCT nt.PostId) AS TotalPostsAllTime,
        COUNT(DISTINCT nt.PostId) FILTER (WHERE nt.CreationDate >= NOW() - INTERVAL '6 months') AS RecentPostsCount,
        COUNT(DISTINCT nt.PostId) FILTER (WHERE nt.CreationDate >= NOW() - INTERVAL '12 months' AND nt.CreationDate < NOW() - INTERVAL '6 months') AS PreviousPostsCount,
        AVG(nt.Score) AS AvgScoreAllTime
    FROM NormalizedTags nt
    GROUP BY nt.TagName
),
TrendingTags AS (
    -- Identify tags that are experiencing significant growth and maintain high quality in posts.
    -- A tag is considered "trending" if it meets minimum activity, score, and growth criteria.
    SELECT
        taw.TagName,
        taw.RecentPostsCount,
        taw.PreviousPostsCount,
        taw.AvgScoreAllTime,
        CASE
            WHEN taw.PreviousPostsCount > 0 THEN CAST(taw.RecentPostsCount AS DECIMAL) / taw.PreviousPostsCount
            ELSE NULL -- Handle new tags or tags with no previous activity
        END AS GrowthFactor
    FROM TagActivityWindow taw
    WHERE taw.RecentPostsCount >= 150 -- Minimum number of posts in the recent period
      AND taw.AvgScoreAllTime >= 5   -- Minimum average score for quality indication
      AND (
          taw.PreviousPostsCount = 0 OR -- Allow newly active tags to trend
          (taw.RecentPostsCount > taw.PreviousPostsCount * 2.0 AND taw.GrowthFactor > 1.5) -- Require significant growth
      )
),
UserRelevantPosts AS (
    -- Filter for high-quality, recent posts (questions/answers) by users in the identified trending tags.
    -- These posts are the core contributions from which user influence will be measured.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        tt.TagName AS TrendingTagName
    FROM Posts p
    JOIN NormalizedTags nt ON p.Id = nt.PostId
    JOIN TrendingTags tt ON nt.TagName = tt.TagName
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2) -- Only questions and answers contribute to expertise
      AND p.Score >= 20 -- High minimum score for post quality
      AND p.ViewCount >= 1000 -- High minimum view count for post visibility
      AND p.CreationDate >= NOW() - INTERVAL '6 months' -- Focus on recent relevant posts
),
UserPostAggregates AS (
    -- Aggregate post-related performance metrics for each user based on their `UserRelevantPosts`.
    -- Collects `RelevantPostIds` into an array for efficient lookups in subsequent CTEs.
    SELECT
        urp.UserId,
        COUNT(DISTINCT urp.PostId) AS TotalRelevantPosts,
        SUM(urp.Score) AS SumRelevantPostScore,
        AVG(urp.Score) AS AvgRelevantPostScore,
        SUM(urp.ViewCount) AS SumRelevantPostViews,
        COUNT(DISTINCT urp.TrendingTagName) AS DistinctTrendingTagsContributed,
        ARRAY_AGG(DISTINCT urp.PostId) AS RelevantPostIds -- Used for filtering related activity
    FROM UserRelevantPosts urp
    GROUP BY urp.UserId
),
UserActivityAndEngagement AS (
    -- Aggregate user's recent activity (badges, comments, edits, votes) that are
    -- either recent or directly related to their `UserRelevantPosts`.
    SELECT
        upa.UserId,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Date >= NOW() - INTERVAL '12 months') AS RecentBadges, -- Badges earned in the last year
        COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate >= NOW() - INTERVAL '6 months' AND c.PostId = ANY(upa.RelevantPostIds)) AS CommentsOnRelevantPosts,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.CreationDate >= NOW() - INTERVAL '6 months' AND ph.PostId = ANY(upa.RelevantPostIds) AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditsOnRelevantPosts, -- Edits on relevant posts
        COUNT(DISTINCT v.Id) FILTER (WHERE v.CreationDate >= NOW() - INTERVAL '6 months' AND v.PostId = ANY(upa.RelevantPostIds) AND v.VoteTypeId = 2) AS UpVotesGivenOnRelevantPosts,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.CreationDate >= NOW() - INTERVAL '6 months' AND v.PostId = ANY(upa.RelevantPostIds) AND v.VoteTypeId = 3) AS DownVotesGivenOnRelevantPosts
    FROM UserPostAggregates upa
    LEFT JOIN Badges b ON upa.UserId = b.UserId
    LEFT JOIN Comments c ON upa.UserId = c.UserId
    LEFT JOIN PostHistory ph ON upa.UserId = ph.UserId
    LEFT JOIN Votes v ON upa.UserId = v.UserId
    GROUP BY upa.UserId
),
UserInfluenceScores AS (
    -- Calculate a comprehensive influence score for each user by combining all aggregated metrics.
    -- Weights are applied to different metrics to reflect their estimated importance.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserOverallUpVotes,
        u.DownVotes AS UserOverallDownVotes,
        u.Views AS UserProfileViews,
        upa.TotalRelevantPosts,
        upa.SumRelevantPostScore,
        upa.AvgRelevantPostScore,
        upa.SumRelevantPostViews,
        upa.DistinctTrendingTagsContributed,
        uae.RecentBadges,
        uae.CommentsOnRelevantPosts,
        uae.EditsOnRelevantPosts,
        (
            (u.Reputation * 0.35) +                                         -- Core reputation (highest weight)
            (upa.SumRelevantPostScore * 0.25) +                             -- Quality of high-visibility contributions
            (upa.SumRelevantPostViews * 0.00005) +                          -- Reach/visibility of contributions (scaled)
            (upa.TotalRelevantPosts * 0.05) +                               -- Quantity of high-quality contributions
            (upa.DistinctTrendingTagsContributed * 0.05) +                  -- Breadth of influence across trending topics
            (uae.RecentBadges * 0.05) +                                     -- Recent achievements indicating sustained effort
            (uae.CommentsOnRelevantPosts * 0.05) +                          -- Direct engagement in community discussions
            (uae.EditsOnRelevantPosts * 0.05) +                             -- Contribution to content improvement
            (COALESCE(CAST(u.UpVotes AS DECIMAL) / NULLIF(u.DownVotes, 0), 0) * 0.05) -- Community's overall positive perception
        ) AS InfluenceScore
    FROM Users u
    JOIN UserPostAggregates upa ON u.Id = upa.UserId
    LEFT JOIN UserActivityAndEngagement uae ON u.Id = uae.UserId
    WHERE u.Reputation >= 20000 -- Significant reputation threshold for "influencers"
      AND upa.TotalRelevantPosts >= 15 -- Minimum number of high-quality posts in trending areas
)
-- Final selection of the top influential users, ordered by their calculated influence score.
SELECT
    uis.DisplayName,
    uis.Reputation,
    ROUND(uis.InfluenceScore, 2) AS InfluenceScore,
    uis.TotalRelevantPosts,
    ROUND(uis.AvgRelevantPostScore, 2) AS AvgRelevantPostScore,
    uis.SumRelevantPostViews,
    uis.DistinctTrendingTagsContributed,
    uis.RecentBadges,
    uis.CommentsOnRelevantPosts,
    uis.EditsOnRelevantPosts,
    uis.UserOverallUpVotes,
    uis.UserOverallDownVotes,
    uis.UserProfileViews,
    ARRAY_AGG(DISTINCT urp.TrendingTagName ORDER BY urp.TrendingTagName) AS InvolvedTrendingTags,
    RANK() OVER (ORDER BY uis.InfluenceScore DESC, uis.Reputation DESC, uis.TotalRelevantPosts DESC) AS InfluenceRank
FROM UserInfluenceScores uis
JOIN UserRelevantPosts urp ON uis.UserId = urp.UserId
GROUP BY
    uis.UserId, uis.DisplayName, uis.Reputation, uis.InfluenceScore,
    uis.TotalRelevantPosts, uis.AvgRelevantPostScore, uis.SumRelevantPostViews,
    uis.DistinctTrendingTagsContributed, uis.RecentBadges, uis.CommentsOnRelevantPosts,
    uis.EditsOnRelevantPosts, uis.UserOverallUpVotes, uis.UserOverallDownVotes,
    uis.UserProfileViews
ORDER BY
    InfluenceRank ASC
LIMIT 25;
