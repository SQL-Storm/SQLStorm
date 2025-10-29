-- {"query": "3311.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2260}
WITH
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT b.Id)                           AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS BronzeBadges,
            MAX(u.LastAccessDate)                         AS LastSeen
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    AnswerStats AS (
        SELECT
            p.OwnerUserId                                    AS UserId,
            COUNT(*)                                         AS AnswerCount,
            AVG(p.Score)                                     AS AvgAnswerScore,
            MAX(CASE WHEN p.Score >= 10 THEN p.CreationDate END) AS LastHighScoreAnswerDate,
            MIN(p.CreationDate)                              AS FirstAnswerDate,
            (SELECT STRING_AGG(DISTINCT tn.tag, ',')
             FROM (
                 SELECT TRIM(BOTH '<>' FROM x.t) AS tag
                 FROM (
                     SELECT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS t
                 ) x
             ) tn
            )                                               AS TagsAnswered
        FROM Posts p
        WHERE p.PostTypeId = 2
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, p.Tags
    ),

    QuestionTagStats AS (
        SELECT
            t.TagName,
            COUNT(DISTINCT p.Id)    AS QuestionCount,
            AVG(p.Score)            AS AvgQuestionScore,
            MAX(p.ViewCount)        AS MaxViews
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT TRIM(BOTH '<>' FROM x.t) AS tag
            FROM (
                SELECT UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS t
            ) x
        ) tn
        JOIN Tags t ON t.TagName = tn.tag
        WHERE p.PostTypeId = 1
        GROUP BY t.TagName
    ),

    TopTags AS (
        SELECT TagName
        FROM QuestionTagStats
        ORDER BY QuestionCount DESC
        LIMIT 10
    ),

    UserTagMatch AS (
        SELECT
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.BadgeCount,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            asr.AnswerCount,
            asr.AvgAnswerScore,
            asr.TagsAnswered,
            COUNT(tt.TagName) AS MatchingTopTagCount
        FROM UserStats us
        LEFT JOIN AnswerStats asr ON asr.UserId = us.Id
        LEFT JOIN TopTags tt ON tt.TagName = ANY(STRING_TO_ARRAY(COALESCE(asr.TagsAnswered, ''), ','))
        GROUP BY
            us.Id, us.DisplayName, us.Reputation, us.BadgeCount,
            us.GoldBadges, us.SilverBadges, us.BronzeBadges,
            asr.AnswerCount, asr.AvgAnswerScore, asr.TagsAnswered
    ),

    RecentVotes AS (
        SELECT
            v.UserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)   AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate)                         AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ),

    Final AS (
        SELECT
            utm.Id,
            utm.DisplayName,
            utm.Reputation,
            utm.BadgeCount,
            utm.GoldBadges,
            utm.SilverBadges,
            utm.BronzeBadges,
            utm.AnswerCount,
            ROUND(CAST(utm.AvgAnswerScore AS NUMERIC), 2)          AS AvgAnswerScore,
            utm.MatchingTopTagCount,
            COALESCE(rv.UpVotes, 0)                         AS UpVotes,
            COALESCE(rv.DownVotes, 0)                       AS DownVotes,
            rv.LastVoteDate,
            ROW_NUMBER() OVER (ORDER BY utm.Reputation DESC, utm.AnswerCount DESC) AS RankByRep
        FROM UserTagMatch utm
        LEFT JOIN RecentVotes rv ON rv.UserId = utm.Id
        WHERE utm.AnswerCount IS NOT NULL
        GROUP BY
            utm.Id, utm.DisplayName, utm.Reputation, utm.BadgeCount,
            utm.GoldBadges, utm.SilverBadges, utm.BronzeBadges,
            utm.AnswerCount, utm.AvgAnswerScore, utm.MatchingTopTagCount,
            rv.UpVotes, rv.DownVotes, rv.LastVoteDate, utm.MatchingTopTagCount
    )

SELECT *
FROM Final
WHERE RankByRep <= 100

UNION ALL

SELECT
    NULL AS Id,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL AS BadgeCount,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS AnswerCount,
    NULL AS AvgAnswerScore,
    NULL AS MatchingTopTagCount,
    NULL AS UpVotes,
    NULL AS DownVotes,
    NULL AS LastVoteDate,
    101 AS RankByRep

ORDER BY RankByRep;