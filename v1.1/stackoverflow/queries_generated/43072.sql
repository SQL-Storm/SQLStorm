-- {"query": "43072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 396} 

WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(Score) AS TotalScore,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT
        u.DisplayName,
        u.Reputation,
        ua.TotalPosts,
        ua.TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '90 days'
    GROUP BY u.Id
    ORDER BY ua.TotalScore DESC, u.Reputation DESC
    LIMIT 10
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.TotalScore,
    tc.BadgeCount,
    ARRAY_AGG(DISTINCT t.TagName) AS TopTags
FROM TopContributors tc
JOIN Posts p ON tc.DisplayName = p.OwnerDisplayName
JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) WITH ORDINALITY t(TagName, pos) ON true
WHERE p.PostTypeId = 1
GROUP BY tc.DisplayName, tc.Reputation, tc.TotalPosts, tc.TotalScore, tc.BadgeCount
ORDER BY tc.TotalScore DESC, COUNT(p.Id) DESC;
