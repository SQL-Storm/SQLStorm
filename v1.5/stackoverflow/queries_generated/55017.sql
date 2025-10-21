-- {"query": "55017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1647} 

WITH
-- 1. Explode every question into (TagId, TagName, QuestionId, Score, CreationDate, OwnerUserId)
exploded_questions AS (
    SELECT
        t.Id                                     AS tag_id,
        t.TagName                                AS tag_name,
        p.Id                                     AS question_id,
        p.Score,
        p.CreationDate,
        p.OwnerUserId
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1                                 -- only questions
     AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')        -- tag appears in the question
),

-- 2. Aggregate basic statistics per tag
tag_question_stats AS (
    SELECT
        tag_id,
        tag_name,
        COUNT(*)                                            AS question_count,
        AVG(score)::NUMERIC(10,2)                           AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score)  AS median_score,
        MIN(CreationDate)                                   AS first_asked,
        MAX(CreationDate)                                   AS latest_asked
    FROM exploded_questions
    GROUP BY tag_id, tag_name
),

-- 3. For each tag, find the top‑scoring answerer (by highest answer score, break ties by earliest answer)
top_answerers AS (
    SELECT
        eq.tag_id,
        a.OwnerUserId                                     AS user_id,
        a.Score                                           AS answer_score,
        a.CreationDate                                    AS answer_date,
        ROW_NUMBER() OVER (PARTITION BY eq.tag_id
                           ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM exploded_questions eq
    JOIN Posts a
      ON a.PostTypeId = 2                                 -- only answers
     AND a.ParentId   = eq.question_id
)
SELECT
    tqs.tag_name,
    tqs.question_count,
    tqs.avg_score,
    tqs.median_score,
    tqs.first_asked,
    tqs.latest_asked,
    jsonb_agg(
        jsonb_build_object(
            'user_id',   ta.user_id,
            'reputation',u.reputation,
            'answer_score',ta.answer_score,
            'answer_date',ta.answer_date
        )
        ORDER BY ta.answer_score DESC, ta.answer_date ASC
    ) FILTER (WHERE ta.rn = 1) AS top_answerer,
    jsonb_object_agg(vt.name, vt.vote_count) AS votes_by_type
FROM tag_question_stats tqs
LEFT JOIN top_answerers ta
  ON ta.tag_id = tqs.tag_id AND ta.rn = 1
LEFT JOIN Users u
  ON u.Id = ta.user_id
LEFT JOIN (
    -- 4. Count votes per vote‑type for each tag (questions only)
    SELECT
        t.Id                                 AS tag_id,
        vt.Name                               AS name,
        COUNT(v.Id)                           AS vote_count
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    JOIN Votes v
      ON v.PostId = p.Id
    JOIN VoteTypes vt
      ON vt.Id = v.VoteTypeId
    GROUP BY t.Id, vt.Name
) vt
  ON vt.tag_id = tqs.tag_id
GROUP BY
    tqs.tag_name,
    tqs.question_count,
    tqs.avg_score,
    tqs.median_score,
    tqs.first_asked,
    tqs.latest_asked
ORDER BY tqs.question_count DESC
LIMIT 100;
