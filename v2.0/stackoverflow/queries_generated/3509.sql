-- {"query": "3509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2160} 

/*  Comprehensive performance‑benchmark query using CTEs, window functions,
    lateral joins, outer joins, correlated sub‑queries, set operators,
    complex expressions and NULL handling                                            */
WITH UserAgg AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(q.CntQ,0)                 AS QuestionCnt,
        COALESCE(a.CntA,0)                 AS AnswerCnt,
        COALESCE(b.Gold,0)                 AS GoldBadges,
        COALESCE(b.Silver,0)               AS SilverBadges,
        COALESCE(b.Bronze,0)               AS BronzeBadges,
        /* latest activity across posts & comments */
        GREATEST(
            COALESCE(q.LastPost, TIMESTAMP '1970‑01‑01'),
            COALESCE(a.LastPost, TIMESTAMP '1970‑01‑01'),
            COALESCE(c.LastComment, TIMESTAMP '1970‑01‑01')
        )                                 AS LastActivity
    FROM Users u
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)               AS CntQ,
            MAX(CreationDate)      AS LastPost
        FROM Posts
        WHERE PostTypeId = 1                 -- questions
        GROUP BY OwnerUserId
    ) q ON q.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*)               AS CntA,
            MAX(CreationDate)      AS LastPost
        FROM Posts
        WHERE PostTypeId = 2                 -- answers
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
    /* total score per tag across all questions */
    SELECT
        tag,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM (
        SELECT
            unnest(string_to_array(
                substring(p.Tags,2,length(p.Tags)-2), '><')) AS tag,
            p.Score
        FROM Posts p
        WHERE p.PostTypeId = 1                -- only questions have tags
    ) t
    GROUP BY tag
),

UserTopTag AS (
    /* most frequent tag used by each user (by question count) */
    SELECT
        ua.UserId,
        t.tag,
        COUNT(*) AS TagUseCnt,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM UserAgg ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            substring(p.Tags,2,length(p.Tags)-2), '><')) AS tag
    ) t
    GROUP BY ua.UserId, t.tag
),

UserWithTopTag AS (
    SELECT
        ua.*,
        COALESCE(ut.tag, 'NoTag')               AS TopTag,
        COALESCE(ts.TotalScore,0)               AS TopTagScore,
        COALESCE(ts.TagRank, NULL)              AS TopTagRank
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
WHERE (uwt.QuestionCnt + uwt.AnswerCnt) > 0               -- active contributors
UNION ALL
/* include completely inactive users to test outer‑join handling */
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0,0,0,0,0,
    'Inactive',
    NULL,
    NULL,NULL,NULL
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY Reputation DESC, QuestionCnt DESC
LIMIT 100;
