WITH EnhBadges AS (
    SELECT
        b.UserId,
        STRING_AGG(
            CASE
                WHEN b.Class = 1 THEN 'Gold: ' || b.Name
                WHEN b.Class = 2 THEN 'Silver: ' || b.Name
                ELSE 'Bronze: ' || b.Name
            END, '; ' ORDER BY b.Date
        ) AS BadgesList,
        COUNT(*) OVER (PARTITION BY b.UserId) AS UserBadgeCount,
        -- Replace COUNT(DISTINCT b.Class) OVER (...) with an aggregate per user to get distinct class count
        (SELECT COUNT(DISTINCT b2.Class) FROM Badges b2 WHERE b2.UserId = b.UserId) AS NexusModifier
    FROM Badges b
    GROUP BY b.UserId
),
LatestEdits AS (
    SELECT
        okqu.Id AS AnswerId,
        MAX(ph.CreationDate) AS LatestEditDate
    FROM PostTypes ptq
    INNER JOIN Posts pq
        ON ptq.Id = pq.PostTypeId
        AND ptq.Name = 'Question'
    JOIN PostHistory ph
        ON ph.PostId = pq.Id
    JOIN Posts okqu
        ON okqu.ParentId = pq.Id
        AND okqu.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer' LIMIT 1)
    GROUP BY okqu.Id
)
SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    e.BadgesList,
    e.UserBadgeCount,
    e.NexusModifier,
    l.LatestEditDate
FROM Posts p
LEFT JOIN EnhBadges e
    ON e.UserId = p.OwnerUserId
LEFT JOIN LatestEdits l
    ON l.AnswerId = p.Id
WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question' LIMIT 1)
GROUP BY
    p.Id,
    p.Title,
    p.OwnerUserId,
    e.BadgesList,
    e.UserBadgeCount,
    e.NexusModifier,
    l.LatestEditDate;