-- {"query": "23088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 914} 

WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000 AND t.TagName NOT LIKE '%test%'
),
UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        COALESCE(MAX(b.Date), u.CreationDate) AS LatestBadgeDate
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(b.Id) > 5 OR u.Reputation > 10000
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, p.CreationDate) AS EffectiveDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        STRING_AGG(SPLIT_PART(tag, '><', 1), ', ') WITHIN GROUP (ORDER BY tag) AS TagList  -- Assuming PostgreSQL-compatible string functions
    FROM Posts p
    CROSS JOIN LATERAL STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS tag
    WHERE p.PostTypeId = 1  -- Questions
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.ClosedDate, p.CreationDate
    UNION ALL
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        NULL AS AnswerCount,
        NULL AS FavoriteCount,
        COALESCE(p.LastActivityDate, p.CreationDate) AS EffectiveDate,
        (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty,  -- Correlated subquery
        NULL AS TagList
    FROM Posts p
    WHERE p.PostTypeId = 2  -- Answers
    AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > p.CreationDate + INTERVAL '1 DAY')
)
SELECT 
    ubs.UserId,
    COALESCE(u.DisplayName, ubs.UserId::varchar) AS UserName,  -- NULL logic
    ubs.Reputation,
    ubs.BadgeCount,
    ubs.GoldBadges,
    pm.PostId,
    pm.Score,
    pm.ViewCount,
    COALESCE(pm.AnswerCount + pm.FavoriteCount, 0) * (pm.Score / NULLIF(pm.PositiveComments + 1, 0)) AS CalculatedMetric,  -- Complicated calculation with NULLIF
    tt.TagName,
    RANK() OVER (PARTITION BY ubs.UserId ORDER BY pm.Score DESC) AS PostRank,
    CASE 
        WHEN pm.TagList IS NOT NULL THEN UPPER(SUBSTRING(pm.TagList FROM 1 FOR 10)) || '...' 
        ELSE 'No Tags' 
    END AS TruncatedTags  -- String expression
FROM UserBadgeSummary ubs
INNER JOIN Posts p ON ubs.UserId = p.OwnerUserId
LEFT OUTER JOIN PostMetrics pm ON p.Id = pm.PostId
LEFT OUTER JOIN TopTags tt ON tt.TagId = (SELECT t2.Id FROM Tags t2 WHERE t2.TagName = SPLIT_PART(pm.TagList, ', ', 1) LIMIT 1)  -- Correlated subquery for tag matching
LEFT OUTER JOIN Users u ON ubs.UserId = u.Id
WHERE ubs.LatestBadgeDate > '2020-01-01'
AND (pm.CalculatedMetric > 10 OR pm.AvgBounty IS NOT NULL)
ORDER BY ubs.Reputation DESC, pm.Score DESC
LIMIT 1000;
