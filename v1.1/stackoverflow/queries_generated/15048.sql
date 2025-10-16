-- {"query": "15048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 114415, "output_tokens": 33684} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostInteractionMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation,
    ubs.BadgeCount,
    ubs.UniqueBadgeTypes,
    pim.PostId,
    pim.Title,
    pim.Tags,
    pim.UniqueVoters,
    pim.CommentCount,
    pim.UpVotes,
    pim.DownVotes,
    RANK() OVER (PARTITION BY ubs.Id ORDER BY pim.UniqueVoters DESC) AS VoterRank,
    COALESCE(pim.UpVotes, 0) - COALESCE(pim.DownVotes, 0) AS NetVotes,
    CASE 
        WHEN pim.UniqueVoters > 10 AND ubs.Reputation > 5000 THEN 'High Impact'
        WHEN pim.UniqueVoters > 5 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory
FROM UserBadgeStats ubs
JOIN PostInteractionMetrics pim ON ubs.UserId = pim.PostId % 1000
WHERE 
    ubs.HasGoldBadge = 1
    AND pim.UniqueVoters > 0
    AND LENGTH(pim.Tags) > 5
ORDER BY 
    NetVotes DESC, 
    ubs.Reputation DESC
LIMIT 100;