-- {"query": "52030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 613} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalVotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagUsage AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(*) AS TagCount
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    JOIN Tags t ON t.TagName = tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
TopTags AS (
    SELECT 
        UserId,
        TagName,
        TagCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
    FROM TagUsage
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.TotalQuestions,
    ups.TotalAnswers,
    ups.TotalQuestionScore,
    ups.TotalAnswerScore,
    ups.TotalComments,
    ups.TotalVotesReceived,
    ups.TotalBadges,
    ups.LastPostActivity,
    ROUND(ups.AvgPostScore, 2) AS AvgPostScore,
    tt.TagName AS TopTag,
    tt.TagCount AS TopTagCount,
    (ups.TotalQuestionScore + ups.TotalAnswerScore) * 10 + ups.TotalBadges * 100 AS ComputedScore
FROM UserPostStats ups
LEFT JOIN TopTags tt ON ups.UserId = tt.UserId AND tt.rn = 1
WHERE ups.TotalPosts > 0
ORDER BY ComputedScore DESC
LIMIT 1000;