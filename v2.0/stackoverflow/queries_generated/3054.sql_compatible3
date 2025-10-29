WITH
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeTotal,
        COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
        STRING_AGG(DISTINCT b.Name, ',') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE(
            EXTRACT(EPOCH FROM (
                SELECT MAX(p.LastActivityDate)
                FROM Posts p
                WHERE p.Id = t.ExcerptPostId
            )), 0) AS RecencyScore
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
),
UserTagScore AS (
    SELECT
        us.Id,
        SUM(
            CASE
                WHEN q.Tags IS NOT NULL THEN
                    (SELECT COALESCE(SUM(tt.RecencyScore), 0)
                     FROM UNNEST(STRING_TO_ARRAY(q.Tags, '><')) AS tag(tag)
                     JOIN TopTags tt ON tt.TagName = tag.tag)
                ELSE 0
            END
        ) AS TagAffinity
    FROM UserStats us
    LEFT JOIN Posts q
        ON q.OwnerUserId = us.Id AND q.PostTypeId = 1
    GROUP BY us.Id
),
Combined AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        ba.BadgeTotal,
        ba.Gold,
        ba.Silver,
        ba.Bronze,
        us.LastPostDate,
        COALESCE(uts.TagAffinity, 0) AS TagAffinity,
        ROW_NUMBER() OVER (PARTITION BY us.Id ORDER BY us.TotalScore DESC) AS rn,
        ba.BadgeNames
    FROM UserStats us
    LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
    LEFT JOIN UserTagScore uts ON uts.Id = us.Id
)
SELECT
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.QuestionCount,
    c.AnswerCount,
    c.TotalScore,
    c.BadgeTotal,
    c.Gold,
    c.Silver,
    c.Bronze,
    c.LastPostDate,
    c.TagAffinity,
    CASE
        WHEN c.Reputation > 100000 THEN 'Legendary'
        WHEN c.Reputation > 20000 THEN 'Expert'
        WHEN c.Reputation > 5000 THEN 'Advanced'
        ELSE 'Intermediate'
    END AS ReputationTier,
    COALESCE(NULLIF(c.BadgeNames, ''), 'None') AS BadgeList
FROM Combined c
WHERE c.rn = 1

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS Id,
    '--- Summary ---' AS DisplayName,
    CAST(NULL AS BIGINT) AS Reputation,
    SUM(c.QuestionCount) AS QuestionCount,
    SUM(c.AnswerCount) AS AnswerCount,
    SUM(c.TotalScore) AS TotalScore,
    SUM(c.BadgeTotal) AS BadgeTotal,
    SUM(c.Gold) AS Gold,
    SUM(c.Silver) AS Silver,
    SUM(c.Bronze) AS Bronze,
    CAST(NULL AS TIMESTAMP) AS LastPostDate,
    AVG(c.TagAffinity) AS TagAffinity,
    'Summary' AS ReputationTier,
    CAST(NULL AS TEXT) AS BadgeList
FROM Combined c
WHERE c.rn = 1
GROUP BY NULL
ORDER BY TotalScore DESC
LIMIT 100;