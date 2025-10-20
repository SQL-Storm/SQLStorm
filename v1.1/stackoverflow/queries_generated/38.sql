-- {"query": "38.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 240} 
WITH cte_users_with_high_reputation AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 100000
),
cte_most_active_users AS (
    SELECT uwhr.Id, uwhr.DisplayName, COUNT(*) AS TotalPosts
    FROM cte_users_with_high_reputation uwhr
    JOIN Posts p ON uwhr.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2021-01-01'
    GROUP BY uwhr.Id, uwhr.DisplayName
    HAVING COUNT(*) > 100
),
cte_top_tags AS (
    SELECT t.TagName, COUNT(*) AS TagCount
    FROM Tags t
    JOIN PostTags pt ON t.Id = pt.TagId
    JOIN Posts p ON pt.PostId = p.Id
    WHERE p.CreationDate >= '2021-01-01'
    GROUP BY t.TagName
    ORDER BY TagCount DESC
    LIMIT 5
)
SELECT mat.DisplayName AS MostActiveUser, tt.TagName AS TopTag, mat.TotalPosts
FROM cte_most_active_users mat
CROSS JOIN cte_top_tags tt;