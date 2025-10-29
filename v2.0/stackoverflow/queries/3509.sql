WITH UserAgg AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(q.CntQ, 0)                 AS QuestionCnt,
        COALESCE(a.CntA, 0)                 AS AnswerCnt,
        COALESCE(b.Gold, 0)                 AS GoldBadges,
        COALESCE(b.Silver, 0)               AS SilverBadges,
        COALESCE(b.Bronze, 0)               AS BronzeBadges,
        GREATEST(
            COALESCE(q.LastPost, TIMESTAMP '1970-01-01'),
            COALESCE(a.LastPost, TIMESTAMP '1970-01-01'),
            COALESCE(c.LastComment, TIMESTAMP '1970-01-01')
        )                                   AS LastActivity
    FROM Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)               AS CntQ,
            MAX(CreationDate)      AS LastPost
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) q ON q.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)               AS CntA,
            MAX(CreationDate)      AS LastPost
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) a ON a.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            UserId,
            MAX(CreationDate) AS LastComment
        FROM Comments
        GROUP BY UserId
    ) c ON c.UserId = u.Id
),

TagScore AS (
    SELECT
        tag,
        SUM(score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY SUM(score) DESC) AS TagRank
    FROM (
        SELECT
            unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><')) AS tag,
            p.Score AS score
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) t
    GROUP BY tag
),

UserTopTag AS (
    SELECT
        ua.UserId,
        t.tag,
        COUNT(*) AS TagUseCnt,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM UserAgg ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><')) AS tag
    ) t
    GROUP BY ua.UserId, t.tag
),

UserWithTopTag AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCnt,
        ua.AnswerCnt,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.LastActivity,
        COALESCE(ut.tag, 'NoTag')               AS TopTag,
        COALESCE(ts.TotalScore, 0)               AS TopTagScore,
        ts.TagRank                               AS TopTagRank
    FROM UserAgg ua
    LEFT JOIN UserTopTag ut
        ON ut.UserId = ua.UserId AND ut.rn = 1
    LEFT JOIN TagScore ts
        ON ts.tag = ut.tag
)

SELECT
    uwt.UserId,
    uwt.DisplayName,
    uwt.Reputation,
    uwt.QuestionCnt,
    uwt.AnswerCnt,
    uwt.GoldBadges,
    uwt.SilverBadges,
    uwt.BronzeBadges,
    CASE
        WHEN uwt.Reputation >= 20000 THEN 'Legendary'
        WHEN uwt.Reputation >= 10000 THEN 'Expert'
        WHEN uwt.Reputation >= 5000  THEN 'Intermediate'
        ELSE 'Novice'
    END                                 AS ReputationTier,
    uwt.LastActivity,
    uwt.TopTag,
    uwt.TopTagScore,
    uwt.TopTagRank
FROM UserWithTopTag uwt
WHERE (uwt.QuestionCnt + uwt.AnswerCnt) > 0

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0 AS QuestionCnt,
    0 AS AnswerCnt,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    'Inactive' AS ReputationTier,
    NULL AS LastActivity,
    NULL AS TopTag,
    NULL AS TopTagScore,
    NULL AS TopTagRank
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC, QuestionCnt DESC
LIMIT 100;