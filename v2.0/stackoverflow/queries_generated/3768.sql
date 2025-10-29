-- {"query": "3768.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2185} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                AS VoteBalance,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)               AS RepRank
    FROM Users u
    WHERE u.Reputation > 1000
),
RecentPosts AS (
    SELECT
        p.OwnerUserId,
        MAX(p.CreationDate)                                        AS LastPostDate,
        SUM(COALESCE(p.Score,0))                                    AS TotalScore,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                  AS QuestionsPosted,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                  AS AnswersPosted
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY p.OwnerUserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE(e.ExcerptLength,0)                                 AS ExcerptLen,
        COALESCE(w.WikiLength,0)                                    AS WikiLen,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC)                  AS TagRank
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
    WHERE t.IsModeratorOnly = 0
),
UserTagActivity AS (
    SELECT
        us.Id,
        us.DisplayName,
        STRING_AGG(DISTINCT tg.TagName, ', ') FILTER (WHERE tg.TagName IS NOT NULL) AS TagsUsed,
        COUNT(DISTINCT tg.TagName)                                 AS DistinctTagCount
    FROM UserStats us
    LEFT JOIN Posts p
        ON p.OwnerUserId = us.Id AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTR(p.Tags,2,LENGTH(p.Tags)-2), '><')) AS TagName
    ) tg ON true
    GROUP BY us.Id, us.DisplayName
),
Combined AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.VoteBalance,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        us.RepRank,
        COALESCE(rp.LastPostDate, TIMESTAMP '1970-01-01')          AS LastPostDate,
        COALESCE(rp.TotalScore,0)                                 AS RecentScore,
        COALESCE(rp.QuestionsPosted,0)                            AS RecentQuestions,
        COALESCE(rp.AnswersPosted,0)                              AS RecentAnswers,
        uta.TagsUsed,
        uta.DistinctTagCount
    FROM UserStats us
    LEFT JOIN RecentPosts rp   ON rp.OwnerUserId = us.Id
    LEFT JOIN UserTagActivity uta ON uta.Id = us.Id
)
SELECT *
FROM Combined
WHERE (RecentScore > 0 AND DistinctTagCount >= 3)
   OR (GoldBadges >= 5 AND Reputation > 20000)
ORDER BY RepRank
LIMIT 100

UNION ALL

SELECT
    NULL                     AS Id,
    'Summary'                AS DisplayName,
    NULL                     AS Reputation,
    NULL                     AS VoteBalance,
    NULL                     AS GoldBadges,
    NULL                     AS SilverBadges,
    NULL                     AS BronzeBadges,
    NULL                     AS QuestionCount,
    NULL                     AS AnswerCount,
    NULL                     AS RepRank,
    MAX(LastPostDate)        AS LastPostDate,
    SUM(RecentScore)         AS RecentScore,
    SUM(RecentQuestions)     AS RecentQuestions,
    SUM(RecentAnswers)       AS RecentAnswers,
    NULL                     AS TagsUsed,
    NULL                     AS DistinctTagCount
FROM Combined
WHERE RepRank IS NOT NULL
EXCEPT
SELECT *
FROM Combined
WHERE RepRank > 2000;
