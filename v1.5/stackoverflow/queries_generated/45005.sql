-- {"query": "45005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 408}
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
    AND p.CreationDate > '2015-01-01'
),
TagAnalysis AS (
    SELECT 
        UserId,
        DisplayName,
        STRING_AGG(DISTINCT UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><')), ', ') AS TopTags,
        AVG(Score) AS AvgPostScore,
        COUNT(*) AS TotalQuestions,
        MAX(Score) AS HighestScore
    FROM RankedUserPosts
    WHERE PostRank <= 5
    GROUP BY UserId, DisplayName
)
SELECT 
    ta.UserId,
    ta.DisplayName,
    ta.TopTags,
    ta.AvgPostScore,
    ta.TotalQuestions,
    ta.HighestScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ta.UserId) AS TotalBadges
FROM TagAnalysis ta
WHERE ta.TotalQuestions > 10
ORDER BY ta.AvgPostScore DESC, ta.TotalQuestions DESC
LIMIT 100;
