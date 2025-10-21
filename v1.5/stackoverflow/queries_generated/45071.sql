-- {"query": "45071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 162874, "output_tokens": 28817} 
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.Tags,
        p.PostTypeId,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY u.Id) AS UpVoteCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > '2015-01-01'
),
TagBreakdown AS (
    SELECT 
        UserId,
        DisplayName,
        array_agg(DISTINCT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><'))) AS UniqueTagsList
    FROM RankedUserPosts
    WHERE ScoreRank <= 3
    GROUP BY UserId, DisplayName
)
SELECT 
    t.DisplayName,
    t.UserId,
    array_length(t.UniqueTagsList, 1) AS UniqueTagCount,
    ROUND(AVG(r.Score), 2) AS AvgTopPostScore,
    MAX(r.UpVoteCount) AS MaxUpVotes,
    COUNT(DISTINCT r.PostId) AS TopPostCount
FROM TagBreakdown t
JOIN RankedUserPosts r ON t.UserId = r.UserId
WHERE r.ScoreRank <= 3 AND r.PostTypeId = 1
GROUP BY t.UserId, t.DisplayName, t.UniqueTagsList
ORDER BY MaxUpVotes DESC, AvgTopPostScore DESC
LIMIT 100;