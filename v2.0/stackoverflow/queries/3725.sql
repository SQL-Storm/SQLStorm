-- {"query": "3725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2232}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT
        u.Id        AS UserId,
        TRIM(t.tag) AS Tag,
        COUNT(*)    AS TagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY u.Id, TRIM(t.tag)
),
TopTags AS (
    SELECT
        tu.UserId,
        STRING_AGG(tu.Tag, ', ') AS Top3Tags
    FROM (
        SELECT
            tu.UserId,
            tu.Tag,
            tu.TagCount,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS rn
        FROM TagUsage tu
    ) tu
    WHERE tu.rn <= 3
    GROUP BY tu.UserId
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END)   AS UpVotesGiven,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesGiven,
        MAX(v.CreationDate)                             AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
      AND v.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY v.UserId
),
MainRows AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        COALESCE(us.AvgQuestionScore, 0) AS AvgQuestionScore,
        COALESCE(us.AvgAnswerScore, 0)   AS AvgAnswerScore,
        COALESCE(bs.GoldBadges, 0)       AS GoldBadges,
        COALESCE(bs.SilverBadges, 0)     AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0)     AS BronzeBadges,
        COALESCE(rv.UpVotesGiven, 0)     AS UpVotesGivenLast30d,
        COALESCE(rv.DownVotesGiven, 0)   AS DownVotesGivenLast30d,
        tt.Top3Tags,
        us.LastPostDate
    FROM UserStats us
    LEFT JOIN BadgeStats   bs ON bs.UserId = us.Id
    LEFT JOIN RecentVotes  rv ON rv.UserId = us.Id
    LEFT JOIN TopTags      tt ON tt.UserId = us.Id
    WHERE (us.QuestionCount + us.AnswerCount) > 0
      AND (us.Reputation IS NULL OR us.Reputation > 100)
),
AggregateRow AS (
    SELECT
        CAST(NULL AS INTEGER)                              AS Id,
        'TOTAL'                                            AS DisplayName,
        SUM(us.Reputation)                                 AS Reputation,
        SUM(us.QuestionCount)                              AS QuestionCount,
        SUM(us.AnswerCount)                                AS AnswerCount,
        AVG(us.AvgQuestionScore)                           AS AvgQuestionScore,
        AVG(us.AvgAnswerScore)                             AS AvgAnswerScore,
        SUM(COALESCE(bs.GoldBadges, 0))                    AS GoldBadges,
        SUM(COALESCE(bs.SilverBadges, 0))                  AS SilverBadges,
        SUM(COALESCE(bs.BronzeBadges, 0))                  AS BronzeBadges,
        SUM(COALESCE(rv.UpVotesGiven, 0))                  AS UpVotesGivenLast30d,
        SUM(COALESCE(rv.DownVotesGiven, 0))                AS DownVotesGivenLast30d,
        CAST(NULL AS VARCHAR)                              AS Top3Tags,
        MAX(us.LastPostDate)                               AS LastPostDate
    FROM UserStats us
    LEFT JOIN BadgeStats   bs ON bs.UserId = us.Id
    LEFT JOIN RecentVotes  rv ON rv.UserId = us.Id
)
SELECT *
FROM (
    SELECT *
    FROM MainRows
    ORDER BY (QuestionCount + AnswerCount) DESC
    LIMIT 100
) main_limited
UNION ALL
SELECT *
FROM AggregateRow;