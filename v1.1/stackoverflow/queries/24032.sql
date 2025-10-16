WITH base AS (
    SELECT u.Id        AS UserId,
           u.Reputation,
           u.DisplayName,
           u.CreationDate,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)  AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)  AS AnswerCount,
           SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END)        AS PositiveScore,
           SUM(CASE WHEN p.Score < 0 THEN p.Score ELSE 0 END)        AS NegativeScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
badges AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges
    GROUP BY UserId
),
post_tags AS (
    -- normalize Tags like '<sql><postgres>' into one tag per row
    SELECT p.Id AS PostId,
           LOWER(TRIM(BOTH '<>' FROM s.tag)) AS Tag
    FROM Posts p,
         LATERAL (
           SELECT v AS tag
           FROM UNNEST(
             CASE
               WHEN p.Tags IS NULL THEN ARRAY[]::varchar[]
               ELSE (
                 STRING_TO_ARRAY(
                   TRIM(BOTH '<>' FROM p.Tags),
                   '><'
                 )
               )
             END
           ) AS t(v)
         ) s
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
final_calc AS (
    SELECT b.UserId,
           b.Reputation,
           b.DisplayName,
           b.QuestionCount,
           b.AnswerCount,
           b.PositiveScore,
           b.NegativeScore,
           COALESCE(bs.Gold, 0) AS Gold,
           COALESCE(bs.Silver, 0) AS Silver,
           COALESCE(bs.Bronze, 0) AS Bronze,
           (b.Reputation + b.PositiveScore + COALESCE(bs.Gold,0)*300
            + COALESCE(bs.Silver,0)*150 + COALESCE(bs.Bronze,0)*75) AS Scoring
    FROM base b
    LEFT JOIN badges bs ON bs.UserId = b.UserId
),
top_rep AS (
    SELECT UserId, Reputation, DisplayName, QuestionCount, AnswerCount,
           PositiveScore, NegativeScore, Gold, Silver, Bronze, Scoring
    FROM final_calc
    WHERE Scoring > 3000
    ORDER BY Reputation DESC
    LIMIT 10
),
top_ans AS (
    SELECT UserId, Reputation, DisplayName, QuestionCount, AnswerCount,
           PositiveScore, NegativeScore, Gold, Silver, Bronze, Scoring
    FROM final_calc
    WHERE Scoring > 3000
    ORDER BY AnswerCount DESC
    LIMIT 10
),
combined AS (
    SELECT * FROM top_rep
    UNION ALL
    SELECT * FROM top_ans
)
SELECT c.UserId,
       c.Reputation,
       c.DisplayName,
       c.QuestionCount,
       c.AnswerCount,
       c.PositiveScore,
       c.NegativeScore,
       c.Gold,
       c.Silver,
       c.Bronze,
       c.Scoring,
       COALESCE((
         SELECT COUNT(*)
         FROM post_tags pt
         JOIN Posts p2 ON p2.Id = pt.PostId
         WHERE p2.OwnerUserId = c.UserId
           AND pt.Tag = 'sql'
       ), 0) AS SqlQuestionCount,
       CASE WHEN c.Scoring > 5000 AND c.Gold > 3 THEN 'Elite' ELSE 'Regular' END AS Category
FROM combined c
ORDER BY c.Scoring DESC, c.Reputation DESC
LIMIT 50;