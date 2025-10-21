-- {"query": "45049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 512}
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    AND p.CreationDate > NOW() - INTERVAL '5 years'
),
UserTagStats AS (
    SELECT 
        UserId,
        DisplayName,
        STRING_AGG(
            (SELECT t.TagName FROM Tags t WHERE t.Id IN (
                SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
            ) LIMIT 1), 
            ',' ORDER BY PostRank
        ) AS TopTags,
        MAX(Score) AS MaxQuestionScore,
        AVG(Score) AS AvgQuestionScore
    FROM RankedUserPosts
    WHERE PostRank <= 5
    GROUP BY UserId, DisplayName
)
SELECT 
    uts.UserId,
    uts.DisplayName,
    uts.TopTags,
    uts.MaxQuestionScore,
    uts.AvgQuestionScore,
    COUNT(v.Id) AS TotalVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount
FROM UserTagStats uts
LEFT JOIN Votes v ON v.UserId = uts.UserId
LEFT JOIN Badges b ON b.UserId = uts.UserId
WHERE uts.AvgQuestionScore > 2
GROUP BY uts.UserId, uts.DisplayName, uts.TopTags, uts.MaxQuestionScore, uts.AvgQuestionScore
ORDER BY TotalVotes DESC
LIMIT 1000;
