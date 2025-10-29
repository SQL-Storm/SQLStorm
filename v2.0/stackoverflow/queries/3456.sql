-- {"query": "3456.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2842}
WITH
    UserPosts AS (
        SELECT
            u.Id                     AS UserId,
            p.Id                     AS PostId,
            p.PostTypeId,
            p.Score,
            p.CreationDate,
            p.Tags,
            p.ViewCount,
            p.FavoriteCount,
            ROW_NUMBER() OVER (PARTITION BY u.Id
                               ORDER BY p.CreationDate DESC) AS rn_latest_post
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    ),
    UserBadges AS (
        SELECT
            u.Id                                 AS UserId,
            COUNT(b.Id)                          AS TotalBadges,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    UserVotes AS (
        SELECT
            u.Id                                 AS UserId,
            COUNT(v.Id)                          AS TotalVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
        FROM Users u
        LEFT JOIN Posts p  ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v  ON v.PostId = p.Id
        GROUP BY u.Id
    ),
    UserTagUsage AS (
        SELECT
            up.UserId,
            LOWER(TRIM(t.tag))                   AS Tag,
            COUNT(*)                             AS TagCount
        FROM UserPosts up
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(up.Tags, '[><]+') AS tag
        ) t
        WHERE up.Tags IS NOT NULL
          AND up.PostTypeId = 1
        GROUP BY up.UserId, LOWER(TRIM(t.tag))
    ),
    RankedTags AS (
        SELECT
            uta.UserId,
            uta.Tag,
            uta.TagCount,
            ROW_NUMBER() OVER (PARTITION BY uta.UserId
                               ORDER BY uta.TagCount DESC, uta.Tag) AS rn_tag
        FROM UserTagUsage uta
    ),
    QuestionSummary AS (
        SELECT
            UserId,
            COUNT(*)                         AS QuestionCount,
            MAX(CreationDate)                AS LastQuestionDate
        FROM UserPosts
        WHERE PostTypeId = 1
        GROUP BY UserId
    ),
    AnswerSummary AS (
        SELECT
            UserId,
            COUNT(*)                         AS AnswerCount,
            MAX(CreationDate)                AS LastAnswerDate
        FROM UserPosts
        WHERE PostTypeId = 2
        GROUP BY UserId
    )

SELECT
    u.Id                                         AS UserId,
    u.DisplayName,
    COALESCE(u.Reputation, 0)                    AS Reputation,
    COALESCE(ub.TotalBadges, 0)                  AS TotalBadges,
    COALESCE(ub.GoldBadges, 0)                   AS GoldBadges,
    COALESCE(ub.SilverBadges, 0)                 AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0)                 AS BronzeBadges,
    COALESCE(uv.TotalVotesReceived, 0)           AS TotalVotesReceived,
    COALESCE(uv.UpVotesReceived, 0)              AS UpVotesReceived,
    COALESCE(uv.DownVotesReceived, 0)            AS DownVotesReceived,
    COALESCE(qs.QuestionCount, 0)                AS QuestionCount,
    COALESCE(asum.AnswerCount, 0)                AS AnswerCount,
    qs.LastQuestionDate,
    asum.LastAnswerDate,
    rt.Tag                                       AS TopTag,
    rt.TagCount                                  AS TopTagUsage
FROM Users u
LEFT JOIN UserBadges   ub   ON ub.UserId   = u.Id
LEFT JOIN UserVotes    uv   ON uv.UserId   = u.Id
LEFT JOIN QuestionSummary qs ON qs.UserId = u.Id
LEFT JOIN AnswerSummary   asum ON asum.UserId = u.Id
LEFT JOIN RankedTags     rt  ON rt.UserId = u.Id AND rt.rn_tag = 1
WHERE u.CreationDate < CAST('2024-10-01' AS DATE)
UNION ALL
SELECT
    -1                                         AS UserId,
    'Aggregated Totals'                        AS DisplayName,
    SUM(COALESCE(u.Reputation, 0))             AS Reputation,
    SUM(COALESCE(ub.TotalBadges, 0))           AS TotalBadges,
    SUM(COALESCE(ub.GoldBadges, 0))            AS GoldBadges,
    SUM(COALESCE(ub.SilverBadges, 0))          AS SilverBadges,
    SUM(COALESCE(ub.BronzeBadges, 0))          AS BronzeBadges,
    SUM(COALESCE(uv.TotalVotesReceived, 0))    AS TotalVotesReceived,
    SUM(COALESCE(uv.UpVotesReceived, 0))       AS UpVotesReceived,
    SUM(COALESCE(uv.DownVotesReceived, 0))     AS DownVotesReceived,
    SUM(COALESCE(qs.QuestionCount, 0))         AS QuestionCount,
    SUM(COALESCE(asum.AnswerCount, 0))         AS AnswerCount,
    MAX(qs.LastQuestionDate)                   AS LastQuestionDate,
    MAX(asum.LastAnswerDate)                   AS LastAnswerDate,
    NULL                                       AS TopTag,
    NULL                                       AS TopTagUsage
FROM Users u
LEFT JOIN UserBadges   ub   ON ub.UserId   = u.Id
LEFT JOIN UserVotes    uv   ON uv.UserId   = u.Id
LEFT JOIN QuestionSummary qs ON qs.UserId = u.Id
LEFT JOIN AnswerSummary   asum ON asum.UserId = u.Id
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;