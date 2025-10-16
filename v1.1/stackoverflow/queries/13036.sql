-- {"query": "13036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 641} 
WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    JOIN Posts p ON ',' || p.Tags || ',' LIKE '%,' || t.TagName || ',%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
AnswerQuality AS (
    SELECT 
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(p.Id) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 0
    GROUP BY p.ParentId
    HAVING COUNT(p.Id) > 2
)
SELECT 
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpVotes,
    ua.DownVotes,
    tt.TagName AS MostUsedTag,
    aq.AvgAnswerScore,
    RANK() OVER (ORDER BY (ua.UpVotes - ua.DownVotes) DESC, aq.AvgAnswerScore DESC) AS PerformanceRank
FROM UserActivity ua
LEFT JOIN Posts q ON ua.Id = q.OwnerUserId AND q.PostTypeId = 1
LEFT JOIN AnswerQuality aq ON q.Id = aq.QuestionId
LEFT JOIN (SELECT * FROM TopTags WHERE TagRank <= 3) tt ON ',' || q.Tags || ',' LIKE '%,' || tt.TagName || ',%'
WHERE ua.LastVoteDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
  AND (ua.UpVotes - ua.DownVotes) > 100
ORDER BY PerformanceRank, ua.DisplayName;