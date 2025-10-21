-- {"query": "28024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1378} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.Reputation,
        u.UpVotes - u.DownVotes AS NetVotes,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        LEAD(u.CreationDate) OVER (ORDER BY u.CreationDate) AS NextUserCreation
    FROM Users u
), PostActivity AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Tags,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) AS TagCount,
        AVG(p.AnswerCount) OVER (PARTITION BY p.PostTypeId) AS AvgAnswersPerType,
        FIRST_VALUE(p.Title) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS HighestScoringPostTitle
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
)
SELECT 
    us.DisplayName,
    us.Location,
    us.NetVotes,
    pa.HighestScoringPostTitle,
    pa.TagCount,
    COALESCE(SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8), 0) AS TotalBounty,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
    STRING_AGG(DISTINCT pt.Name, '; ') AS PostTypes,
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary' 
        WHEN us.Reputation > 10000 THEN 'Epic' 
        WHEN us.Reputation > 1000 THEN 'Advanced' 
        ELSE 'Basic' 
    END AS ReputationClass,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.Id AND c.Score > 5) AS HighScoreComments
FROM UserStats us
LEFT JOIN PostActivity pa ON us.Id = pa.OwnerUserId
LEFT JOIN Votes v ON us.Id = v.UserId AND v.VoteTypeId IN (2, 8)
LEFT JOIN PostHistory ph ON pa.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN PostTypes pt ON pa.PostTypeId = pt.Id
WHERE us.GoldBadges > 0 OR pa.TagCount > 5
GROUP BY us.Id, us.DisplayName, us.Location, us.NetVotes, pa.HighestScoringPostTitle, pa.TagCount, us.Reputation
HAVING COUNT(pa.Id) > 10 OR SUM(pa.Score) > 100
UNION ALL
SELECT 
    'SYSTEM' AS DisplayName,
    'N/A' AS Location,
    0 AS NetVotes,
    NULL AS HighestScoringPostTitle,
    NULL AS TagCount,
    0 AS TotalBounty,
    COUNT(*) AS CloseVotes,
    'Automated Closure' AS PostTypes,
    'System' AS ReputationClass,
    0 AS HighScoreComments
FROM PostHistory ph
WHERE ph.PostHistoryTypeId = 10 AND ph.UserId IS NULL
ORDER BY TotalBounty DESC, NetVotes DESC;