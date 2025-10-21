-- {"query": "35089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 561} 
WITH user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        MAX(u.Reputation) AS MaxReputation,
        DATE_TRUNC('month', u.CreationDate) AS SignupMonth
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('month', u.CreationDate)
),
most_used_tags AS (
    SELECT
        t.TagName,
        SUM(t.Count) AS TotalUsage
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TotalUsage DESC
    LIMIT 20
),
tag_post_popularity AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS PostsWithTag,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViews
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY Tag
)
SELECT
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.TotalComments,
    u.TotalAnswers,
    u.TotalUpvotes,
    u.TotalDownvotes,
    u.MaxReputation,
    u.SignupMonth,
    tpt.Tag,
    tpt.PostsWithTag,
    tpt.AvgScore,
    tpt.AvgViews
FROM user_activity u
JOIN Posts p ON p.OwnerUserId = u.UserId
CROSS JOIN LATERAL (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
) pt
JOIN most_used_tags mut ON mut.TagName = pt.Tag
JOIN tag_post_popularity tpt ON tpt.Tag = pt.Tag
WHERE u.TotalPosts > 10 AND u.MaxReputation > 1000
ORDER BY u.MaxReputation DESC, tpt.AvgViews DESC
LIMIT 100;