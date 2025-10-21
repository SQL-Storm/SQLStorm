-- {"query": "23027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1157} 

WITH TopTags AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.PostId
),
ComplexPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        COALESCE(va.Upvotes, 0) - COALESCE(va.Downvotes, 0) AS NetVotes,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT OUTER JOIN VoteAnalysis va ON p.Id = va.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND (p.Tags LIKE '%sql%' OR p.Tags LIKE '%database%')
      AND p.CreationDate > '2020-01-01'
      AND EXISTS (SELECT 1 FROM TopTags tt WHERE strpos(p.Tags, tt.TagName) > 0)
),
MergedData AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.UserLocation,
        us.PostCount,
        us.AvgPostScore,
        us.TotalQuestionViews,
        us.LatestPostDate,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        bs.BadgeNames,
        cp.Title AS TopPostTitle,
        cp.Tags AS TopPostTags,
        cp.Score AS TopPostScore,
        cp.PositiveComments,
        cp.NetVotes,
        ROW_NUMBER() OVER (PARTITION BY us.UserLocation ORDER BY us.Reputation DESC) AS LocationRank
    FROM UserStats us
    LEFT OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT OUTER JOIN ComplexPosts cp ON us.UserId = cp.OwnerUserId AND cp.PostRank = 1
    WHERE us.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
      AND (bs.GoldBadges > 0 OR us.PostCount > 10)
)
SELECT 
    md.UserId,
    md.DisplayName,
    md.UserLocation,
    md.Reputation,
    md.PostCount,
    md.AvgPostScore,
    md.TotalQuestionViews,
    md.GoldBadges,
    md.SilverBadges,
    md.BadgeNames,
    md.TopPostTitle,
    md.TopPostTags,
    md.TopPostScore,
    md.PositiveComments,
    md.NetVotes,
    md.LocationRank,
    CASE 
        WHEN md.LocationRank = 1 THEN 'Top in Location'
        WHEN md.LocationRank <= 5 THEN 'High Rank'
        ELSE 'Other'
    END AS RankCategory,
    NULLIF(md.TopPostScore * md.NetVotes, 0) AS WeightedScore
FROM MergedData md
WHERE md.LocationRank <= 10

UNION ALL

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    u.Reputation,
    0 AS PostCount,
    NULL AS AvgPostScore,
    0 AS TotalQuestionViews,
    0 AS GoldBadges,
    0 AS SilverBadges,
    NULL AS BadgeNames,
    NULL AS TopPostTitle,
    NULL AS TopPostTags,
    NULL AS TopPostScore,
    0 AS PositiveComments,
    0 AS NetVotes,
    NULL AS LocationRank,
    'Inactive' AS RankCategory,
    NULL AS WeightedScore
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation < 100
ORDER BY Reputation DESC
LIMIT 100;
