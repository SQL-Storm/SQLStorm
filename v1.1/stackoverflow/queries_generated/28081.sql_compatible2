WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
),
RankedUsers AS (
    SELECT 
        us.*,
        DENSE_RANK() OVER (ORDER BY us.BadgeCount DESC) AS BadgeRank,
        NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile,
        COALESCE(u.WebsiteUrl, 'No Website') AS WebsiteInfo,
        CASE 
            WHEN u.Reputation > 100000 THEN 'Elite'
            WHEN u.Reputation BETWEEN 50000 AND 100000 THEN 'Advanced'
            ELSE 'Standard'
        END AS ReputationTier,
        u.Reputation,
        u.CreationDate
    FROM UserStats us
    JOIN Users u ON us.UserId = u.Id
    WHERE u.CreationDate >= DATE '2010-01-01'
)
SELECT 
    ru.UserId,
    ru.BadgeRank,
    ru.ReputationTier,
    ru.WebsiteInfo,
    p.Id AS PostId,
    p.Title,
    string_to_array(replace(replace(p.Tags, '<', ''), '>', ','), ',') AS CleanedTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS PostUpVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRank,
    ph.CreationDate AS LastEditDate,
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN 'Closed: ' || crt.Name 
        ELSE COALESCE(ph.Comment, 'No Edit Reason') 
    END AS EditStatus,
    SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViews
FROM RankedUsers ru
LEFT JOIN Posts p ON ru.UserId = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN (
    SELECT PostId, COUNT(*) AS UpVotes 
    FROM Votes 
    WHERE VoteTypeId = 2 
    GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 10)
LEFT JOIN CloseReasonTypes crt ON (CASE WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS INTEGER) ELSE NULL END) = crt.Id
WHERE ru.ReputationQuartile = 1
    AND (ru.QuestionCount > 10 OR ru.AnswerCount > 50)
    AND (p.Body ILIKE '%SQL%' OR p.Body IS NULL)
    AND (p.ClosedDate IS NULL OR p.ClosedDate > DATE '2022-01-01')
UNION ALL
SELECT 
    ru.UserId,
    ru.BadgeRank,
    ru.ReputationTier,
    ru.WebsiteInfo,
    NULL AS PostId,
    NULL AS Title,
    ARRAY['N/A'] AS CleanedTags,
    0 AS CommentCount,
    0 AS PostUpVotes,
    0 AS PostRank,
    NULL AS LastEditDate,
    'No Posts' AS EditStatus,
    0 AS CumulativeViews
FROM RankedUsers ru
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = ru.UserId)
ORDER BY BadgeRank, PostRank NULLS LAST;