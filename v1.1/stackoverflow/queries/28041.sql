WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5,6) THEN 1 ELSE 0 END) AS EditActions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3,8)
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
    GROUP BY u.Id
),
BadgeSummary AS (
    SELECT 
        UserId,
        (SELECT MAX(b2.Name)
         FROM Badges b2
         WHERE b2.UserId = b.UserId
           AND b2.Date = (SELECT MAX(b3.Date) FROM Badges b3 WHERE b3.UserId = b.UserId)
        ) AS LastBadge,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges b
    GROUP BY UserId
)
SELECT 
    u.DisplayName || ' (' || COALESCE(u.Location, 'Unknown') || ')' AS UserLabel,
    EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
    u.Reputation,
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
    bs.LastBadge,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.AvgQuestionScore,
    ua.EditActions,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2 
       AND p2.Score > (SELECT AVG(pA.Score) FROM Posts pA WHERE pA.PostTypeId = 2)
    ) AS HighQualityAnswers,
    (SELECT STRING_AGG(tag, ', ')
     FROM (
        SELECT TRIM(t.tag) AS tag
        FROM Posts p3
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(COALESCE(p3.Tags, ''), '\s+') AS tag
        ) AS t
        WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 1
     ) t_tags
    ) AS TopTags
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN BadgeSummary bs ON u.Id = bs.UserId
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
          AND p4.ClosedDate IS NOT NULL 
          AND p4.Score < 0
    )
    AND u.Id IN (
        SELECT UserId FROM Badges WHERE Class = 1
        INTERSECT
        SELECT UserId FROM Badges WHERE Name LIKE '%Moderator%'
    )
ORDER BY 
    LocationRank,
    u.Reputation DESC
LIMIT 100;