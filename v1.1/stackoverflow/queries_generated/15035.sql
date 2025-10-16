-- {"query": "15035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 84060, "output_tokens": 25183} 
WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        MAX(p.Score) AS MaxScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t ON 1=1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    aut.UserId,
    aut.DisplayName,
    aut.TagName,
    aut.PostCount,
    aut.MaxScore,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    COALESCE(v.UpvoteCount, 0) AS UpvoteCount,
    ROUND(aut.PostCount * (1.0 + LOG(aut.MaxScore + 1)), 2) AS ContributionScore,
    CASE 
        WHEN aut.PostCount > 100 THEN 'Top Contributor'
        WHEN aut.PostCount > 50 THEN 'Active Contributor'
        ELSE 'Emerging Contributor'
    END AS ContributorLevel
FROM ActiveUserTags aut
JOIN UserBadgeStats ubs ON aut.UserId = ubs.UserId
LEFT JOIN (
    SELECT 
        PostId, 
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpvoteCount
    FROM Votes
    GROUP BY PostId
) v ON EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.Id = v.PostId 
      AND p.OwnerUserId = aut.UserId 
      AND p.Tags LIKE '%' || aut.TagName || '%'
)
WHERE aut.TagRank <= 3
  AND (aut.PostCount > 10 OR ubs.GoldBadges > 0)
ORDER BY ContributionScore DESC
LIMIT 100;