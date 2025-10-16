-- {"query": "21065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1389} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(v.BountyAmount) AS AvgBountyGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate > NOW() - INTERVAL '1 year'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8 AND v.BountyAmount > 0
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5 OR u.Reputation > 1000
),
HighImpactPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.ViewCount DESC, p.Score DESC) AS ViewRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.Title) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostTitle,
        NTILE(4) OVER (ORDER BY p.ViewCount DESC) AS PopularityQuartile
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE (p.PostTypeId = 1 AND p.AnswerCount > 0) OR (p.PostTypeId = 2 AND p.Score > 5)
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '30 days')
        AND LENGTH(COALESCE(p.Title, '')) > 10
        AND p.Tags IS NOT NULL AND p.Tags != '<>'
),
RecentActivity AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS EditorId,
        COUNT(*) AS EditCount,
        STRING_AGG(
            COALESCE(ph.Comment, 
                CASE 
                    WHEN ph.PostHistoryTypeId IN (4,7) THEN 'Title edit: ' || SUBSTRING(ph.Text, 1, 50)
                    WHEN ph.PostHistoryTypeId IN (5,8) THEN 'Body edit: ' || SUBSTRING(ph.Text, 1, 50)
                    ELSE 'Other change'
                END
            ), '; '
        ) AS EditSummary
    FROM PostHistory ph
    WHERE ph.CreationDate > NOW() - INTERVAL '6 months'
        AND ph.PostHistoryTypeId IN (4,5,6,10,11)
        AND ph.Text IS NOT NULL
        AND (ph.UserId IS NOT NULL OR ph.UserDisplayName IS NOT NULL)
    GROUP BY ph.PostId, ph.CreationDate, ph.UserId
)
SELECT 
    au.UserId,
    au.Reputation,
    au.TotalPosts,
    au.QuestionCount,
    au.AnswerCount,
    hip.PostId,
    hip.Title,
    hip.Score AS PostScore,
    hip.ViewCount,
    hip.ViewRank,
    hip.PopularityQuartile,
    ra.EditCount,
    ra.EditSummary,
    CASE 
        WHEN hip.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN hip.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN au.Reputation > 5000 AND hip.Score > 100 THEN 'Elite'
        ELSE 'Standard'
    END AS PostStatus,
    COALESCE(hip.AnswerCount, 0) * au.Reputation AS ImpactScore,
    (hip.ViewCount / NULLIF(hip.Score, 0)) AS ViewPerScoreRatio,
    UPPER(SUBSTRING(hip.Tags FROM 2 FOR 20)) AS FirstFewTags,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = au.UserId AND b.Date > au.CreationDate 
     AND b.Class = 1 AND b.TagBased = TRUE) AS GoldTagBadges,
    (SELECT STRING_AGG(DISTINCT lt.Name, ', ') 
     FROM PostLinks pl 
     INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id 
     WHERE pl.PostId = hip.PostId AND pl.CreationDate > hip.CreationDate - INTERVAL '1 month') AS RecentLinkTypes
FROM ActiveUsers au
INNER JOIN HighImpactPosts hip ON au.UserId = hip.OwnerUserId
LEFT JOIN RecentActivity ra ON hip.PostId = ra.PostId
LEFT JOIN Posts p2 ON hip.PostId = p2.Id  -- Self-join for NULL handling
WHERE au.CreationDate < NOW() - INTERVAL '1 year'
    AND (hip.PopularityQuartile <= 2 OR hip.ViewRank <= 10)
    AND (ra.EditCount > 1 OR ra.EditCount IS NULL)
    AND NOT EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = hip.PostId 
        AND v.VoteTypeId = 3  -- DownMod
        AND v.CreationDate > hip.CreationDate
        GROUP BY v.PostId 
        HAVING COUNT(*) > 5
    )
UNION ALL
SELECT 
    NULL AS UserId,
    0 AS Reputation,
    0 AS TotalPosts,
    0 AS QuestionCount,
    0 AS AnswerCount,
    NULL AS PostId,
    'Summary Stats' AS Title,
    SUM(hip.Score) AS PostScore,
    SUM(hip.ViewCount) AS ViewCount,
    COUNT(hip.PostId) AS ViewRank,
    NULL AS PopularityQuartile,
    SUM(ra.EditCount) AS EditCount,
    NULL AS EditSummary,
    'Aggregate' AS PostStatus,
    AVG(COALESCE(hip.AnswerCount, 0)) * AVG(au.Reputation) AS ImpactScore,
    AVG(hip.ViewCount / NULLIF(hip.Score, 0)) AS ViewPerScoreRatio,
    NULL AS FirstFewTags,
    COUNT(DISTINCT au.UserId) AS GoldTagBadges,
    NULL AS RecentLinkTypes
FROM ActiveUsers au
INNER JOIN HighImpactPosts hip ON au.UserId = hip.OwnerUserId
LEFT JOIN RecentActivity ra ON hip.PostId = ra.PostId
ORDER BY ImpactScore DESC, ViewCount DESC
LIMIT 1000;
