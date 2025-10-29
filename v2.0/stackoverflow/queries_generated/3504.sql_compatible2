WITH 
user_agg AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(pcnt.TotalPosts,0)                AS PostCount,
        COALESCE(pcnt.QuestionPosts,0)             AS QuestionCount,
        COALESCE(pcnt.AnswerPosts,0)               AS AnswerCount,
        COALESCE(bcnt.Gold,0)                      AS GoldBadges,
        COALESCE(bcnt.Silver,0)                    AS SilverBadges,
        COALESCE(bcnt.Bronze,0)                    AS BronzeBadges,
        COALESCE(tagcnt.DistinctTags,0)            AS TagContribution,
        (
            SELECT MAX(COALESCE(p.LastActivityDate,p.CreationDate))
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
        )                                          AS LastPostActivity,
        (
            SELECT MAX(v.CreationDate)
            FROM Votes v
            WHERE v.UserId = u.Id
        )                                          AS LastVoteDate
    FROM Users u
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            COUNT(*)                                    AS TotalPosts,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionPosts,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerPosts
        FROM Posts
        GROUP BY OwnerUserId
    ) pcnt ON pcnt.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) bcnt ON bcnt.UserId = u.Id
    LEFT JOIN (
        -- Replace set-returning in aggregate by lateral expansion per post, then count distinct tags per owner
        SELECT 
            p.OwnerUserId,
            COUNT(DISTINCT tag) AS DistinctTags
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT TRIM(t) AS tag
            FROM (
                -- split tags like '<tag1><tag2>' into rows by replacing angle brackets and splitting on '><'
                SELECT regexp_split_to_table(REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'), '><') AS t
            ) s
        ) tags
        WHERE p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId
    ) tagcnt ON tagcnt.OwnerUserId = u.Id
),

ranked_users AS (
    SELECT 
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TagContribution,
        ua.LastPostActivity,
        ua.LastVoteDate,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.PostCount DESC)            AS RepRank,
        RANK()      OVER (PARTITION BY 
                         CASE WHEN ua.GoldBadges > 0 THEN 'Gold' ELSE 'NoGold' END 
                         ORDER BY ua.Reputation DESC)                               AS TierRank
    FROM user_agg ua
),

recent_mod_actions AS (
    SELECT 
        u.Id,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS LastDeleted
    FROM Users u
    LEFT JOIN Posts p            ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph    ON ph.PostId = p.Id
    GROUP BY u.Id
)

SELECT 
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.TagContribution,
    CASE 
        WHEN ru.LastPostActivity IS NULL THEN 'NeverPosted'
        WHEN ru.LastPostActivity > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY) THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus,
    COALESCE(rma.LastClosed, rma.LastDeleted)               AS LastModerationAction,
    ru.RepRank,
    ru.TierRank
FROM ranked_users ru
LEFT JOIN recent_mod_actions rma ON rma.Id = ru.Id
WHERE ru.RepRank <= 1000

UNION ALL

SELECT 
    -1                                 AS Id,
    'Benchmark Dummy'                  AS DisplayName,
    0                                   AS Reputation,
    0                                   AS PostCount,
    0                                   AS QuestionCount,
    0                                   AS AnswerCount,
    0                                   AS GoldBadges,
    0                                   AS SilverBadges,
    0                                   AS BronzeBadges,
    0                                   AS TagContribution,
    'Dummy'                             AS ActivityStatus,
    NULL                                AS LastModerationAction,
    NULL                                AS RepRank,
    NULL                                AS TierRank

ORDER BY Reputation DESC NULLS LAST
LIMIT 1010;