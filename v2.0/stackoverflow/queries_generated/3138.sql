-- {"query": "3138.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1989} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TagUsage AS (
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p          ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS tag(tag_raw) ON TRUE
    JOIN Tags t           ON t.TagName = tag.tag_raw
    GROUP BY u.Id, t.TagName
),

BadgeAggregates AS (
    SELECT
        b.UserId,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.RepRank,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotesReceived,
    us.DownVotesReceived,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.TotalBadges,
    COALESCE(tu.TagName, 'NoTag')      AS TopTag,
    COALESCE(tu.TagCount, 0)           AS TopTagCount,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Posts a
            WHERE a.PostTypeId = 2
              AND a.OwnerUserId = us.Id
              AND a.Id = (
                  SELECT p.AcceptedAnswerId
                  FROM Posts p
                  WHERE p.PostTypeId = 1
                    AND p.AcceptedAnswerId IS NOT NULL
                    AND p.OwnerUserId <> us.Id
                  LIMIT 1
              )
        ) THEN 1 ELSE 0
    END AS HasAcceptedAnswer
FROM UserStats us
LEFT JOIN BadgeAggregates ba ON ba.UserId = us.Id
LEFT JOIN (
    SELECT UserId, TagName, TagCount
    FROM TagUsage
    WHERE TagRank = 1
) tu ON tu.UserId = us.Id
WHERE us.Reputation > 1000

UNION ALL

SELECT
    NULL AS Id,
    'Aggregate' AS DisplayName,
    SUM(us.Reputation)           AS Reputation,
    NULL                         AS RepRank,
    SUM(us.QuestionCount)        AS QuestionCount,
    SUM(us.AnswerCount)          AS AnswerCount,
    SUM(us.UpVotesReceived)      AS UpVotesReceived,
    SUM(us.DownVotesReceived)    AS DownVotesReceived,
    NULL                         AS GoldBadges,
    NULL                         AS SilverBadges,
    NULL                         AS BronzeBadges,
    NULL                         AS TotalBadges,
    NULL                         AS TopTag,
    NULL                         AS TopTagCount,
    NULL                         AS HasAcceptedAnswer
FROM UserStats us
WHERE us.Reputation > 1000;
