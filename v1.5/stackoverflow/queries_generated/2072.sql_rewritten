-- {"query": "2072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 459} 
WITH TopReputationUsers AS (
    SELECT 
        Id AS UserId, 
        DisplayName, 
        Reputation,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
    WHERE Reputation IS NOT NULL
),
TopTags AS (
    SELECT 
        t.TagName, 
        COUNT(p.Id) AS PostCount
    FROM Tags t
    INNER JOIN Posts p ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[t.TagName]
    GROUP BY t.TagName
    HAVING COUNT(p.Id) >= 10
),
UserPostDetails AS (
    SELECT 
        p.OwnerUserId, 
        p.PostTypeId, 
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' AND (p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0)
    GROUP BY p.OwnerUserId, p.PostTypeId
),
CommentActivity AS (
    SELECT 
        c.UserId, 
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.CreationDate >= '2020-01-01'
    GROUP BY c.UserId
)
SELECT 
    tru.DisplayName, 
    tru.Reputation,
    coalesce(ups.AvgScore, 0) AS AveragePostScore, 
    coalesce(ca.TotalComments, 0) AS NumberOfComments,
    coalesce(ca.TotalCommentScore, 0) AS TotalCommentScore,
    CASE 
        WHEN tru.Reputation > 20000 THEN 'Gold'
        WHEN tru.Reputation > 10000 THEN 'Silver'
        ELSE 'Bronze'
    END AS ReputationTier
FROM TopReputationUsers tru
LEFT JOIN UserPostDetails ups ON tru.UserId = ups.OwnerUserId AND ups.PostTypeId = 1
LEFT JOIN CommentActivity ca ON tru.UserId = ca.UserId
WHERE tru.Rank <= 50
ORDER BY tru.Reputation DESC, ca.TotalCommentScore DESC;