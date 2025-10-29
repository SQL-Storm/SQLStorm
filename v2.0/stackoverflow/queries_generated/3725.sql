-- {"query": "3725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2232} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation,0) AS Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
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
        u.Id          AS UserId,
        trim(t.tag)   AS Tag,
        COUNT(*)      AS TagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(
            regexp_replace(p.Tags, '^<|>$', '', 'g'),   -- strip leading/trailing '<' '>'
            '><'
        )) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY u.Id, Tag
),
TopTags AS (
    SELECT
        tu.UserId,
        STRING_AGG(tu.Tag, ', ') FILTER (WHERE rn <= 3) AS Top3Tags
    FROM (
        SELECT
            tu.*,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS rn
        FROM TagUsage tu
    ) tu
    GROUP BY tu.UserId
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
      AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    COALESCE(us.AvgQuestionScore,0) AS AvgQuestionScore,
    COALESCE(us.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(bs.GoldBadges,0)    AS GoldBadges,
    COALESCE(bs.SilverBadges,0)  AS SilverBadges,
    COALESCE(bs.BronzeBadges,0)  AS BronzeBadges,
    COALESCE(rv.UpVotesGiven,0)  AS UpVotesGivenLast30d,
    COALESCE(rv.DownVotesGiven,0) AS DownVotesGivenLast30d,
    tt.Top3Tags,
    us.LastPostDate
FROM UserStats us
LEFT JOIN BadgeStats   bs ON bs.UserId = us.Id
LEFT JOIN RecentVotes  rv ON rv.UserId = us.Id
LEFT JOIN TopTags      tt ON tt.UserId = us.Id
WHERE (us.QuestionCount + us.AnswerCount) > 0
  AND (us.Reputation IS NULL OR us.Reputation > 100)
ORDER BY (us.QuestionCount + us.AnswerCount) DESC
LIMIT 100

UNION ALL

SELECT
    NULL                              AS Id,
    'TOTAL'                           AS DisplayName,
    SUM(us.Reputation)                AS Reputation,
    SUM(us.QuestionCount)             AS QuestionCount,
    SUM(us.AnswerCount)               AS AnswerCount,
    AVG(us.AvgQuestionScore)          AS AvgQuestionScore,
    AVG(us.AvgAnswerScore)            AS AvgAnswerScore,
    SUM(COALESCE(bs.GoldBadges,0))    AS GoldBadges,
    SUM(COALESCE(bs.SilverBadges,0))  AS SilverBadges,
    SUM(COALESCE(bs.BronzeBadges,0))  AS BronzeBadges,
    SUM(COALESCE(rv.UpVotesGiven,0))  AS UpVotesGivenLast30d,
    SUM(COALESCE(rv.DownVotesGiven,0)) AS DownVotesGivenLast30d,
    NULL                              AS Top3Tags,
    MAX(us.LastPostDate)              AS LastPostDate
FROM UserStats us
LEFT JOIN BadgeStats   bs ON bs.UserId = us.Id
LEFT JOIN RecentVotes  rv ON rv.UserId = us.Id;
