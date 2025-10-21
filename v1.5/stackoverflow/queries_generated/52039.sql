-- {"query": "52039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 667} 
WITH user_stats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT v.Id) AS TotalUpvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2  -- Upvote
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
tag_usage AS (
    SELECT 
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagPosts,
        AVG(p.Score) AS AvgTagScore
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
    GROUP BY p.OwnerUserId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalPostScore,
    us.TotalComments,
    ROUND(us.AvgPostScore, 2) AS AvgPostScore,
    us.TotalUpvotesReceived,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    STRING_AGG(DISTINCT tu.TagName || ': ' || tu.TagPosts || ' posts, avg score ' || ROUND(tu.AvgTagScore, 2), '; ') AS TopTags,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalUpvotesReceived DESC) AS Rank
FROM user_stats us
LEFT JOIN badge_stats bs ON us.UserId = bs.UserId
LEFT JOIN tag_usage tu ON us.UserId = tu.OwnerUserId
WHERE us.TotalPosts > 0
GROUP BY us.UserId, us.DisplayName, us.Reputation, us.TotalPosts, us.TotalPostScore, us.TotalComments, us.AvgPostScore, us.TotalUpvotesReceived, bs.TotalBadges, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
ORDER BY Rank
LIMIT 100;