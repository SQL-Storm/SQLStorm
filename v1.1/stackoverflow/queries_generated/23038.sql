-- {"query": "23038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 884} 

WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(b.Date) AS LatestBadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, b.Class
    HAVING COUNT(b.Id) > 0 OR u.Reputation > 1000
),
RecentPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.Title,
        COALESCE(p.Tags, '<no-tags>') AS Tags,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PrevScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
      AND (p.Score > 10 OR p.ViewCount IS NULL OR NULLIF(p.AnswerCount, 0) > 5)
),
AggregatedVotes AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Votes v
    GROUP BY v.UserId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.Reputation + COALESCE(rp.Score, 0) AS AdjustedReputation,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.LatestBadgeDate,
    ubs.BadgeRank,
    rp.PostId,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.TagArray,
    rp.PrevScore,
    rp.PositiveComments,
    av.UpvotesGiven,
    av.DownvotesGiven,
    CASE 
        WHEN rp.Score > ubs.Reputation / 10 THEN 'High Impact'
        WHEN rp.Score IS NULL THEN 'No Recent Activity'
        ELSE CONCAT('Average: ', CAST(AVG(rp.Score) OVER (PARTITION BY ubs.UserId) AS VARCHAR))
    END AS PerformanceCategory
FROM UserBadgeStats ubs
FULL OUTER JOIN RecentPosts rp ON ubs.UserId = rp.OwnerUserId
LEFT JOIN AggregatedVotes av ON ubs.UserId = av.UserId
WHERE ubs.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
   OR EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (10, 11))
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(Reputation) AS AdjustedReputation,
    SUM(TotalBadges) AS TotalBadges,
    SUM(GoldBadges) AS GoldBadges,
    MAX(LatestBadgeDate) AS LatestBadgeDate,
    NULL AS BadgeRank,
    NULL AS PostId,
    AVG(Score) AS Score,
    SUM(ViewCount) AS ViewCount,
    NULL AS Title,
    NULL AS Tags,
    NULL AS TagArray,
    NULL AS PrevScore,
    SUM(PositiveComments) AS PositiveComments,
    SUM(UpvotesGiven) AS UpvotesGiven,
    SUM(DownvotesGiven) AS DownvotesGiven,
    'Aggregate' AS PerformanceCategory
FROM UserBadgeStats ubs
INNER JOIN RecentPosts rp ON ubs.UserId = rp.OwnerUserId
LEFT JOIN AggregatedVotes av ON ubs.UserId = av.UserId
ORDER BY AdjustedReputation DESC
LIMIT 100;
