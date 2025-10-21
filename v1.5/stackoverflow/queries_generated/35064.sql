-- {"query": "35064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 690} 
WITH top_users AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(p.Id) AS TotalPosts, 
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        u.Reputation,
        u.UpVotes,
        u.DownVotes
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    HAVING COUNT(p.Id) > 100
    ORDER BY Reputation DESC
    LIMIT 50
),
user_activity AS (
    SELECT 
        tu.UserId,
        COUNT(DISTINCT ph.Id) AS Edits,
        COUNT(DISTINCT c.Id) AS Comments
    FROM top_users tu
    LEFT JOIN Posts p ON p.OwnerUserId = tu.UserId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = tu.UserId
    LEFT JOIN Comments c ON c.UserId = tu.UserId
    GROUP BY tu.UserId
),
user_badges AS (
    SELECT
        tu.UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM top_users tu
    LEFT JOIN Badges b ON b.UserId = tu.UserId
    GROUP BY tu.UserId
),
favorite_tags AS (
    SELECT 
        tu.UserId,
        t.TagName,
        SUM(1) AS TagPosts
    FROM top_users tu
    JOIN Posts p ON p.OwnerUserId = tu.UserId AND p.PostTypeId = 1
    JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_str ON TRUE
    JOIN Tags t ON t.TagName = tag_str
    GROUP BY tu.UserId, t.TagName
),
top_tags AS (
    SELECT 
        UserId,
        TagName,
        TagPosts,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPosts DESC) AS rn
    FROM favorite_tags
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.UpVotes,
    tu.DownVotes,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    ua.Edits,
    ua.Comments,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tt.TagName AS TopTag,
    tt.TagPosts AS TopTagCount
FROM top_users tu
LEFT JOIN user_activity ua ON ua.UserId = tu.UserId
LEFT JOIN user_badges ub ON ub.UserId = tu.UserId
LEFT JOIN top_tags tt ON tt.UserId = tu.UserId AND tt.rn = 1
ORDER BY tu.Reputation DESC, tu.TotalPosts DESC
LIMIT 50;