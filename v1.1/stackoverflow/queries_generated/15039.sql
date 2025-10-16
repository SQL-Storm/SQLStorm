-- {"query": "15039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 93400, "output_tokens": 27836} 
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Votes v 
             WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)),
            0
        ) AS TotalVotes,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 
    AND u.Reputation > 1000
), TopUserPosts AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(Score) AS TotalPostScore,
        AVG(TotalVotes) AS AvgVotesPerPost,
        COUNT(DISTINCT PostId) AS UniquePostCount,
        SUM(IsClosed) AS ClosedPostCount
    FROM RankedUserPosts
    WHERE PostRank <= 5
    GROUP BY UserId, DisplayName
)
SELECT 
    tup.UserId,
    tup.DisplayName,
    tup.TotalPostScore,
    tup.AvgVotesPerPost,
    tup.UniquePostCount,
    tup.ClosedPostCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tup.UserId) AS BadgeCount,
    DENSE_RANK() OVER (ORDER BY tup.TotalPostScore DESC) AS ScoreRank
FROM TopUserPosts tup
LEFT JOIN Tags t ON 
    CAST(REPLACE(REPLACE(t.TagName, '<', ''), '>', '') AS VARCHAR) IN (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
        FROM Posts p
        WHERE p.OwnerUserId = tup.UserId
)
WHERE tup.UniquePostCount > 1
AND (tup.AvgVotesPerPost > 5 OR tup.TotalPostScore > 100)
ORDER BY ScoreRank, TotalPostScore DESC
LIMIT 50;