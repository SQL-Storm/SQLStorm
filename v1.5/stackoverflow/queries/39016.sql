-- {"query": "39016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1912} 
WITH TopTags AS (
    SELECT
        tag AS TagName,
        COUNT(p.Id) AS QuestionCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag(tag)
    WHERE p.PostTypeId = 1
    GROUP BY tag
),
MonthlyAnswers AS (
    SELECT
        date_trunc('month', a.CreationDate)      AS month,
        u.Id                                     AS user_id,
        u.DisplayName                            AS user_name,
        COUNT(*)                                 AS answer_count,
        AVG(a.Score)                             AS avg_score,
        MAX(a.Score)                             AS max_score
    FROM Posts a
    JOIN Users u
      ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
    GROUP BY date_trunc('month', a.CreationDate), u.Id, u.DisplayName
),
BadgeMatrix AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    ma.month,
    ma.user_id,
    ma.user_name,
    ma.answer_count,
    ma.avg_score,
    ma.max_score,
    COALESCE(bm.gold_badges,   0) AS gold_badges,
    COALESCE(bm.silver_badges, 0) AS silver_badges,
    COALESCE(bm.bronze_badges, 0) AS bronze_badges,
    tt.TagName                AS top_tag,
    tt.QuestionCount          AS tag_questions,
    DENSE_RANK() OVER (
        PARTITION BY ma.month
        ORDER BY ma.avg_score DESC
    )                         AS rank_by_score,
    PERCENT_RANK() OVER (
        PARTITION BY ma.month
        ORDER BY ma.answer_count
    )                         AS pct_rank_by_answers
FROM MonthlyAnswers ma
LEFT JOIN BadgeMatrix bm
  ON bm.UserId = ma.user_id
LEFT JOIN (
    SELECT TagName, QuestionCount
    FROM TopTags
    WHERE TagRank <= 3
) tt
  ON TRUE
WHERE ma.answer_count > 10
ORDER BY ma.month DESC, rank_by_score
LIMIT 50;