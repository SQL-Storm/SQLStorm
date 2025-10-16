-- {"query": "23055.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 807} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(CASE WHEN p.Tags IS NOT NULL THEN substring(p.Tags, 2, length(p.Tags)-2) ELSE '' END, ', ') AS AllTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
    GROUP BY u.Id
    HAVING COUNT(p.Id) > 0 OR u.Reputation > 1000
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.TagBased = 1
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
        (SELECT MAX(CreationDate) FROM Votes WHERE PostId = v.PostId AND VoteTypeId IN (8,9)) AS BountyDate
    FROM Votes v
    GROUP BY v.PostId
),
CombinedStats AS (
    SELECT 
        ups.UserId,
        ups.TotalPosts,
        ups.Questions,
        ups.Answers,
        ups.AvgScore,
        ups.LastPostDate,
        ups.AllTags,
        bs.TotalBadges,
        bs.GoldBadges,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = ups.UserId AND c.Score > 5) AS HighScoreComments,
        RANK() OVER (ORDER BY ups.AvgScore DESC NULLS LAST) AS ScoreRank
    FROM UserPostStats ups
    FULL OUTER JOIN BadgeStats bs ON ups.UserId = bs.UserId AND bs.BadgeRank = 1
    WHERE ups.AllTags LIKE '%sql%' OR bs.GoldBadges > 0
)
SELECT 
    cs.UserId,
    cs.TotalPosts,
    cs.Questions,
    cs.Answers,
    cs.AvgScore,
    cs.LastPostDate,
    cs.AllTags,
    cs.TotalBadges,
    cs.GoldBadges,
    cs.HighScoreComments,
    cs.ScoreRank,
    COALESCE(va.NetVotes, 0) AS PostNetVotes,
    CASE 
        WHEN cs.LastPostDate IS NULL THEN 'No Posts'
        WHEN va.BountyDate IS NOT NULL THEN CONCAT('Bounty on ', TO_CHAR(va.BountyDate, 'YYYY-MM-DD'))
        ELSE 'No Bounty'
    END AS BountyStatus
FROM CombinedStats cs
LEFT JOIN (
    SELECT PostId, NetVotes, BountyDate
    FROM VoteAnalysis
    WHERE NetVotes > 10
    UNION
    SELECT p.Id AS PostId, 0 AS NetVotes, NULL AS BountyDate
    FROM Posts p
    WHERE p.Score < 0 AND NOT EXISTS (SELECT 1 FROM VoteAnalysis va2 WHERE va2.PostId = p.Id)
) va ON va.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = cs.UserId)
WHERE cs.ScoreRank <= 100
ORDER BY cs.ScoreRank;
