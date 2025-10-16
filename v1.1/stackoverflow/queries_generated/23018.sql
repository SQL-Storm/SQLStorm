-- {"query": "23018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 674} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users) * 2
),
UserPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        COALESCE(p.Tags, '<no tags>') AS Tags,
        CASE 
            WHEN p.ClosedDate IS NULL THEN 'Open' 
            ELSE 'Closed' 
        END AS Status,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    WHERE b.Class = 1 -- Gold badges
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE -1 END) AS NetVotes
    FROM Votes v
    GROUP BY v.PostId
),
Combined AS (
    SELECT 
        tu.UserId,
        tu.Reputation,
        tu.DisplayName,
        tu.Rank,
        up.PostId,
        up.Score,
        up.ViewCount,
        up.Title,
        up.Tags,
        up.Status,
        up.PrevScore,
        up.PositiveComments,
        ub.BadgeCount,
        ub.BadgeNames,
        uv.NetVotes,
        COALESCE(up.Score + uv.NetVotes, 0) AS TotalScore
    FROM TopUsers tu
    LEFT OUTER JOIN UserPosts up ON tu.UserId = up.OwnerUserId
    LEFT OUTER JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT OUTER JOIN UserVotes uv ON up.PostId = uv.PostId
    WHERE up.Score > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = tu.UserId)
       OR up.PostId IS NULL
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Rank,
    COUNT(PostId) OVER (PARTITION BY UserId) AS PostCount,
    AVG(TotalScore) OVER (PARTITION BY UserId) AS AvgTotalScore,
    MAX(BadgeNames) AS TopBadges,
    STRING_AGG(Title || ' (' || Tags || ')', '; ') AS PostSummaries
FROM Combined
GROUP BY UserId, DisplayName, Reputation, Rank
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(Reputation) AS Reputation,
    NULL AS Rank,
    COUNT(PostId) AS PostCount,
    AVG(TotalScore) AS AvgTotalScore,
    NULL AS TopBadges,
    NULL AS PostSummaries
FROM Combined
ORDER BY Reputation DESC;