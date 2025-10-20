-- {"query": "2014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 438} 

WITH RecursiveTagPosts AS (
    SELECT
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0) AS NumTags
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
    ORDER BY
        p.CreationDate DESC
),
TopTagUsers AS (
    SELECT
        DisplayName,
        SUM(NumTags) AS TotalTags
    FROM
        RecursiveTagPosts
    GROUP BY
        DisplayName
),
BadgeRankings AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 3 WHEN Class = 2 THEN 2 ELSE 1 END) AS Score
    FROM
        Badges
    GROUP BY
        UserId
)
SELECT
    u.DisplayName,
    u.Reputation,
    COALESCE(b.Score, 0) AS BadgeScore,
    COALESCE(r.TotalTags, 0) AS TotalPostTags,
    ARRAY_AGG(DISTINCT p.Title || ' (ID: ' || p.Id || ')') AS RecentQuestions
FROM
    Users u
LEFT JOIN
    BadgeRankings b ON u.Id = b.UserId
LEFT JOIN
    TopTagUsers r ON u.DisplayName = r.DisplayName
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN
    Comments c ON p.Id = c.PostId
WHERE
    u.Reputation > 1000
    AND COALESCE(p.CreationDate, u.CreationDate) > CURRENT_DATE - INTERVAL '1 year'
    AND c.Id IS NULL
GROUP BY
    u.DisplayName, u.Reputation, b.Score, r.TotalTags
ORDER BY
    u.Reputation DESC, BadgeScore DESC, TotalPostTags DESC
LIMIT 50;
