-- {"query": "3313.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1556} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]')               AS Location,
        COUNT(b.Id)          FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id)          FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id)          FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)    AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount,
        COUNT(c.Id)                                           AS CommentCount
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadges DESC, SilverBadges DESC) AS ReputationRank
    FROM UserStats
)
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.Location,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalQuestionScore,
    ru.TotalAnswerScore,
    ru.CommentCount,
    ROUND(CASE WHEN ru.QuestionCount = 0 THEN NULL 
               ELSE ru.TotalQuestionScore::numeric/ru.QuestionCount END, 2) AS AvgQuestionScore,
    ROUND(CASE WHEN ru.AnswerCount = 0 THEN NULL 
               ELSE ru.TotalAnswerScore::numeric/ru.AnswerCount END, 2)   AS AvgAnswerScore,
    COALESCE(vs.VoteScore, 0)                                         AS RecentVoteScore,
    COALESCE(t.TagList, '')                                          AS TagList
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS VoteScore
    FROM Votes v
    WHERE v.UserId = ru.Id
      AND v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
) vs ON TRUE
LEFT JOIN LATERAL (
    SELECT STRING_AGG(DISTINCT tg.TagName, ', ') AS TagList
    FROM Posts p
    JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS tgname ON TRUE
    JOIN Tags tg ON tg.TagName = tgname
    WHERE p.OwnerUserId = ru.Id
      AND p.PostTypeId = 1
) t ON TRUE
WHERE ru.ReputationRank <= 100
ORDER BY ru.ReputationRank

UNION ALL

SELECT 
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM generate_series(1,5) g(i);
