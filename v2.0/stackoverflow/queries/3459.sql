-- {"query": "3459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2535}
WITH UserPostAgg AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)    AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)    AS AvgAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COALESCE(SUM(p.FavoriteCount),0)                AS FavoriteSum
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserBadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                    AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

UserTagUsage AS (
    SELECT
        p.OwnerUserId                         AS UserId,
        LOWER(TRIM(t))                        AS Tag,
        COUNT(*)                              AS TagCount
    FROM Posts p,
         LATERAL (SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t)
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, LOWER(TRIM(t))
),

UserTopTag AS (
    SELECT
        ut.UserId,
        ut.Tag      AS TopTag,
        ut.TagCount
    FROM (
        SELECT
            ut.*,
            ROW_NUMBER() OVER (PARTITION BY ut.UserId
                               ORDER BY ut.TagCount DESC, ut.Tag) AS rn
        FROM UserTagUsage ut
    ) ut
    WHERE ut.rn = 1
),

UserActivityWindow AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgQuestionScore,
        upa.AvgAnswerScore,
        upa.UpVoteCount,
        upa.DownVoteCount,
        upa.FavoriteSum,
        RANK()        OVER (ORDER BY upa.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY upa.Reputation)      AS ReputationPct
    FROM UserPostAgg upa
),

MainRows AS (
    SELECT
        uaw.UserId,
        uaw.DisplayName,
        uaw.Reputation,
        uaw.QuestionCount,
        uaw.AnswerCount,
        ROUND(CAST(uaw.AvgQuestionScore AS NUMERIC),2) AS AvgQuestionScore,
        ROUND(CAST(uaw.AvgAnswerScore AS NUMERIC),2)   AS AvgAnswerScore,
        COALESCE(ub.GoldBadges,0)    AS GoldBadges,
        COALESCE(ub.SilverBadges,0)  AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)  AS BronzeBadges,
        COALESCE(ub.TotalBadges,0)   AS TotalBadges,
        COALESCE(ut.TopTag,'<none>') AS TopTag,
        COALESCE(ut.TagCount,0)      AS TopTagUsage,
        uaw.UpVoteCount,
        uaw.DownVoteCount,
        CASE
            WHEN uaw.DownVoteCount = 0 THEN NULL
            ELSE ROUND(CAST(uaw.UpVoteCount AS NUMERIC) / CAST(uaw.DownVoteCount AS NUMERIC),2)
        END                           AS UpDownRatio,
        uaw.FavoriteSum,
        uaw.ReputationRank,
        uaw.ReputationPct
    FROM UserActivityWindow uaw
    LEFT JOIN UserBadgeAgg    ub ON ub.UserId = uaw.UserId
    LEFT JOIN UserTopTag      ut ON ut.UserId = uaw.UserId
    WHERE uaw.Reputation > 1000
      AND (uaw.QuestionCount + uaw.AnswerCount) >= 10
),

TotalRow AS (
    SELECT
        CAST(NULL AS INTEGER)            AS UserId,
        'TOTAL'         AS DisplayName,
        SUM(uaw.Reputation)               AS Reputation,
        SUM(uaw.QuestionCount)            AS QuestionCount,
        SUM(uaw.AnswerCount)              AS AnswerCount,
        CAST(NULL AS NUMERIC)                               AS AvgQuestionScore,
        CAST(NULL AS NUMERIC)                               AS AvgAnswerScore,
        CAST(NULL AS INTEGER)                               AS GoldBadges,
        CAST(NULL AS INTEGER)                               AS SilverBadges,
        CAST(NULL AS INTEGER)                               AS BronzeBadges,
        CAST(NULL AS INTEGER)                               AS TotalBadges,
        CAST(NULL AS TEXT)                                  AS TopTag,
        CAST(NULL AS INTEGER)                               AS TopTagUsage,
        CAST(NULL AS INTEGER)                               AS UpVoteCount,
        CAST(NULL AS INTEGER)                               AS DownVoteCount,
        CAST(NULL AS NUMERIC)                               AS UpDownRatio,
        CAST(NULL AS INTEGER)                               AS FavoriteSum,
        CAST(NULL AS BIGINT)                                AS ReputationRank,
        CAST(NULL AS NUMERIC)                               AS ReputationPct
    FROM UserActivityWindow uaw
    WHERE uaw.Reputation > 1000
      AND (uaw.QuestionCount + uaw.AnswerCount) >= 10
)

SELECT *
FROM (
    SELECT * FROM MainRows
    UNION ALL
    SELECT * FROM TotalRow
) t
ORDER BY ReputationRank
LIMIT 100;