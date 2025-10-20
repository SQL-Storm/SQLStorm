WITH NormalizedTags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
      AND p.PostTypeId IN (1, 2)
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
),
TagActivityWindow AS (
    SELECT
        nt.TagName,
        COUNT(DISTINCT nt.PostId) AS TotalPostsAllTime,
        COUNT(DISTINCT nt.PostId) FILTER (WHERE nt.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') AS RecentPostsCount,
        COUNT(DISTINCT nt.PostId) FILTER (WHERE nt.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months' AND nt.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') AS PreviousPostsCount,
        AVG(nt.Score) AS AvgScoreAllTime
    FROM NormalizedTags nt
    GROUP BY nt.TagName
),
TrendingTags AS (
    SELECT
        taw.TagName,
        taw.RecentPostsCount,
        taw.PreviousPostsCount,
        taw.AvgScoreAllTime,
        CASE
            WHEN taw.PreviousPostsCount > 0 THEN CAST(taw.RecentPostsCount AS DECIMAL) / taw.PreviousPostsCount
            ELSE NULL
        END AS GrowthFactor
    FROM TagActivityWindow taw
    WHERE taw.RecentPostsCount >= 150
      AND taw.AvgScoreAllTime >= 5
      AND (
          taw.PreviousPostsCount = 0
          OR (taw.RecentPostsCount > taw.PreviousPostsCount * 2.0 AND (CAST(taw.RecentPostsCount AS DECIMAL) / NULLIF(taw.PreviousPostsCount, 0)) > 1.5)
      )
),
UserRelevantPosts AS (
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
      AND p.PostTypeId IN (1, 2)
      AND p.Score >= 20
      AND p.ViewCount >= 1000
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
),
UserPostAggregates AS (
    SELECT
        urp.UserId,
        COUNT(DISTINCT urp.PostId) AS TotalRelevantPosts,
        SUM(urp.Score) AS SumRelevantPostScore,
        AVG(urp.Score) AS AvgRelevantPostScore,
        SUM(urp.ViewCount) AS SumRelevantPostViews,
        COUNT(DISTINCT urp.TrendingTagName) AS DistinctTrendingTagsContributed,
        ARRAY_AGG(DISTINCT urp.PostId) AS RelevantPostIds
    FROM UserRelevantPosts urp
    GROUP BY urp.UserId
),
UserActivityAndEngagement AS (
    SELECT
        upa.UserId,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months') AS RecentBadges,
        COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' AND c.PostId = ANY(upa.RelevantPostIds)) AS CommentsOnRelevantPosts,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' AND ph.PostId = ANY(upa.RelevantPostIds) AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditsOnRelevantPosts,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' AND v.PostId = ANY(upa.RelevantPostIds) AND v.VoteTypeId = 2) AS UpVotesGivenOnRelevantPosts,
        COUNT(DISTINCT v2.Id) FILTER (WHERE v2.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months' AND v2.PostId = ANY(upa.RelevantPostIds) AND v2.VoteTypeId = 3) AS DownVotesGivenOnRelevantPosts
    FROM UserPostAggregates upa
    LEFT JOIN Badges b ON upa.UserId = b.UserId
    LEFT JOIN Comments c ON upa.UserId = c.UserId
    LEFT JOIN PostHistory ph ON upa.UserId = ph.UserId
    LEFT JOIN Votes v ON upa.UserId = v.UserId AND v.VoteTypeId = 2
    LEFT JOIN Votes v2 ON upa.UserId = v2.UserId AND v2.VoteTypeId = 3
    GROUP BY upa.UserId
),
UserInfluenceScores AS (
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
            (u.Reputation * 0.35) +
            (upa.SumRelevantPostScore * 0.25) +
            (upa.SumRelevantPostViews * 0.00005) +
            (upa.TotalRelevantPosts * 0.05) +
            (upa.DistinctTrendingTagsContributed * 0.05) +
            (uae.RecentBadges * 0.05) +
            (uae.CommentsOnRelevantPosts * 0.05) +
            (uae.EditsOnRelevantPosts * 0.05) +
            (COALESCE(CAST(u.UpVotes AS DECIMAL) / NULLIF(u.DownVotes, 0), 0) * 0.05)
        ) AS InfluenceScore
    FROM Users u
    JOIN UserPostAggregates upa ON u.Id = upa.UserId
    LEFT JOIN UserActivityAndEngagement uae ON u.Id = uae.UserId
    WHERE u.Reputation >= 20000
      AND upa.TotalRelevantPosts >= 15
)
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
    ARRAY_AGG(urp.TrendingTagName ORDER BY urp.TrendingTagName) FILTER (WHERE urp.TrendingTagName IS NOT NULL) AS InvolvedTrendingTags,
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