-- {"query": "3701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1607} 
WITH RecentPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Tags
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
),

UserBadgeAgg AS (
    SELECT
        u.Id                           AS UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),

UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(uba.GoldBadges,   0) AS GoldBadges,
        COALESCE(uba.SilverBadges, 0) AS SilverBadges,
        COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
        /* correlated subqueries for post counts */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    LEFT JOIN UserBadgeAgg uba ON uba.UserId = u.Id
),

TopActiveUsers AS (
    SELECT
        us.*,
        ROW_NUMBER() OVER (ORDER BY (us.QuestionCount + us.AnswerCount) DESC,
                                      us.Reputation DESC) AS ActivityRank
    FROM UserStats us
    WHERE (us.QuestionCount + us.AnswerCount) > 0
),

TagStats AS (
    SELECT
        UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag,
        p.Score,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags IS NOT NULL
),

TagAggregates AS (
    SELECT
        t.Tag,
        COUNT(*)                AS QuestionUses,
        AVG(t.Score)            AS AvgScore,
        MAX(t.CreationDate)     AS LatestQuestion
    FROM TagStats t
    GROUP BY t.Tag
),

FinalResult AS (
    SELECT
        tu.ActivityRank,
        tu.Id                     AS UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.QuestionCount,
        tu.AnswerCount,
        COALESCE(tagg.QuestionUses, 0)    AS TagQuestionUses,
        COALESCE(tagg.AvgScore,     0)    AS TagAvgScore,
        tagg.LatestQuestion
    FROM TopActiveUsers tu
    /* LATERAL join to fetch the most popular tag for the user (or NULL) */
    LEFT JOIN LATERAL (
        SELECT *
        FROM TagAggregates ta
        ORDER BY ta.QuestionUses DESC
        LIMIT 1
    ) tagg ON TRUE
    WHERE tu.ActivityRank <= 10
)

SELECT *
FROM FinalResult

UNION ALL

/* Second set: the same rows but only for users whose reputation exceeds the global average */
SELECT
    ActivityRank,
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    QuestionCount,
    AnswerCount,
    TagQuestionUses,
    TagAvgScore,
    LatestQuestion
FROM FinalResult
WHERE Reputation > (SELECT AVG(Reputation) FROM Users)

ORDER BY ActivityRank;