-- {"query": "15043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 102740, "output_tokens": 30407} 
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS CreationSequence,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)),
            0
        ) AS TotalVotes
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    AND p.Score > 10
), TagAnalysis AS (
    SELECT 
        UserId,
        DisplayName,
        STRING_AGG(
            CASE 
                WHEN PostRank <= 3 THEN Title 
                ELSE NULL 
            END, 
            ' | ' ORDER BY PostRank
        ) AS TopPosts,
        AVG(TotalVotes) AS AvgVotesPerPost,
        COUNT(PostId) AS TotalQualifyingPosts,
        MAX(Score) AS HighestScore
    FROM RankedUserPosts
    GROUP BY UserId, DisplayName
)
SELECT 
    ta.UserId,
    ta.DisplayName,
    ta.TopPosts,
    ta.AvgVotesPerPost,
    ta.TotalQualifyingPosts,
    ta.HighestScore,
    CASE 
        WHEN ta.TotalQualifyingPosts > 10 THEN 'Prolific'
        WHEN ta.TotalQualifyingPosts > 5 THEN 'Active'
        ELSE 'Occasional'
    END AS ContributionLevel,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ta.UserId) AS BadgeCount
FROM TagAnalysis ta
LEFT JOIN Users u ON ta.UserId = u.Id
WHERE ta.AvgVotesPerPost > 5
AND u.Reputation > 100
ORDER BY ta.HighestScore DESC, ta.AvgVotesPerPost DESC
LIMIT 250;