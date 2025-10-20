-- {"query": "52059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 679} 
WITH RankedUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        SUM(v.BountyAmount) AS TotalBountyEarned,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 9
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2008-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags ELSE NULL END, ', ') AS SampleTags
    FROM Tags t
    JOIN Posts p ON t.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 100
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MIN(c.CreationDate) AS FirstCommentDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
    HAVING COUNT(*) > 5
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.TotalAnswers,
    ru.AvgAnswerScore,
    ru.TotalBountyEarned,
    ru.BadgeCount,
    ts.TagName AS TopTag,
    ts.AvgScore AS TopTagAvgScore,
    ca.CommentCount,
    ca.AvgCommentScore,
    ca.LastCommentDate - ca.FirstCommentDate AS CommentActivitySpan
FROM RankedUsers ru
JOIN Posts p ON ru.UserId = p.OwnerUserId AND p.Score = (SELECT MAX(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = ru.UserId AND p2.PostTypeId = 2)
JOIN TagStats ts ON ts.TagName = (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) LIMIT 1)
LEFT JOIN CommentActivity ca ON p.Id = ca.PostId
WHERE ru.RepRank <= 100
ORDER BY ru.Reputation DESC, ru.TotalAnswers DESC
LIMIT 50;