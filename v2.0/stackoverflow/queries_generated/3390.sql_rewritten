-- {"query": "3390.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2099} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswerCount,
        COALESCE(SUM(p.Score),0)                       AS TotalScore,
        MAX(p.CreationDate)                           AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                     AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count                                    AS TagUseCount,
        COALESCE(e.ExcerptLength,0)                AS ExcerptLength,
        COALESCE(w.WikiLength,0)                   AS WikiLength
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS ExcerptLength
        FROM Posts p
        WHERE p.Id = t.ExcerptPostId
    ) e ON true
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS WikiLength
        FROM Posts p
        WHERE p.Id = t.WikiPostId
    ) w ON true
),
TopUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        ba.GoldBadges,
        ba.SilverBadges,
        ba.BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalScore DESC) AS RN,
        us.LastPostDate
    FROM UserStats us
    LEFT JOIN BadgeAgg ba ON ba.UserId = us.Id
    WHERE us.Reputation > 1000
      AND (us.QuestionCount + us.AnswerCount) >= 10
      AND (ba.GoldBadges IS NULL OR ba.GoldBadges >= 1)
)
SELECT 
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    COALESCE(tu.GoldBadges,0)   AS GoldBadges,
    COALESCE(tu.SilverBadges,0) AS SilverBadges,
    COALESCE(tu.BronzeBadges,0) AS BronzeBadges,
    CASE
        WHEN tu.LastPostDate IS NULL                     THEN 'Never posted'
        WHEN tu.LastPostDate < cast('2024-10-01' as date) - INTERVAL '1 year' THEN 'Stale'
        ELSE 'Active'
    END AS ActivityStatus,
    STRING_AGG(DISTINCT tg.TagName, ', ') FILTER (WHERE tg.TagName IS NOT NULL) AS PopularTags
FROM TopUsers tu
LEFT JOIN Posts p 
       ON p.OwnerUserId = tu.Id 
      AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(
        REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'), 
        '><')) AS TagName
) tg ON true
LEFT JOIN TagStats ts ON ts.TagName = tg.TagName
WHERE ts.TagUseCount > 5000
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation, tu.QuestionCount,
    tu.AnswerCount, tu.TotalScore, tu.GoldBadges, tu.SilverBadges,
    tu.BronzeBadges, tu.LastPostDate
HAVING COUNT(DISTINCT ts.TagName) >= 2

UNION ALL

SELECT 
    NULL AS Id,
    'Aggregate Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    SUM(TotalScore) AS TotalScore,
    SUM(GoldBadges)  AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    NULL AS ActivityStatus,
    NULL AS PopularTags
FROM TopUsers;