-- {"query": "24065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2035} 

WITH question_posts AS (
    SELECT
        p.Id                    AS question_id,
        p.Title,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_relations AS (
    SELECT
        regexp_split_to_array(substring(qp.Tags FROM 2 FOR length(qp.Tags)-2), '><') AS tag_arr,
        qp.question_id,
        qp.Title,
        qp.Score,
        qp.CreationDate,
        qp.OwnerUserId
    FROM question_posts qp
),
exploded_tags AS (
    SELECT
        unnest(tr.tag_arr) AS tag_name,
        tr.question_id,
        tr.Title,
        tr.Score,
        tr.CreationDate,
        tr.OwnerUserId
    FROM tag_relations tr
),
tag_stats AS (
    SELECT
        tag_name,
        COUNT(*)                     AS question_count,
        ROUND(AVG(Score),2)           AS avg_score,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS tag_rank
    FROM exploded_tags
    GROUP BY tag_name
),
latest_q_per_tag AS (
    SELECT
        tag_name,
        question_id,
        Title,
        CreationDate,
        Score,
        ROW_NUMBER() OVER (PARTITION BY tag_name ORDER BY CreationDate DESC) AS rn
    FROM exploded_tags
),
duplicate_counts AS (
    SELECT
        pl.RelatedPostId     AS question_id,
        COUNT(*)             AS dup_count
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3                     -- duplicate link
    GROUP BY pl.RelatedPostId
),
bounty_counts AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT v.Id) AS bounty_started
    FROM Posts p
    JOIN Votes v
      ON v.PostId = p.Id AND v.VoteTypeId = 8   -- bounty start
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
user_tag_counts AS (
    SELECT
        u.Id,
        COUNT(*) AS tags_with_counts
    FROM Tags t
    JOIN Posts p
      ON t.WikiPostId = p.Id                      -- tag wiki
    JOIN Users u
      ON p.OwnerUserId = u.Id
    GROUP BY u.Id
)
SELECT
    ts.tag_name                          AS tag,
    ts.question_count                    AS q_count,
    ts.avg_score                         AS avg_score,
    lq.question_id                       AS latest_q_id,
    lq.Title                             AS latest_q_title,
    lq.CreationDate                      AS latest_q_date,
    COALESCE(b.bounty_started,0)         AS bounty_start_count,
    COALESCE(uc.tags_with_counts,0)      AS user_tag_contribs,
    COALESCE(dc.dup_count,0)             AS duplicate_posts,
    u.DisplayName                        AS owner_name,
    LOWER(ts.tag_name)                   AS tag_lower,
    CASE
        WHEN ts.question_count > 1000 THEN 'Popular'
        WHEN ts.question_count BETWEEN 500 AND 1000 THEN 'Moderate'
        ELSE 'Rare'
    END                                   AS tag_popularity
FROM tag_stats ts
LEFT JOIN latest_q_per_tag lq
  ON lq.tag_name = ts.tag_name AND lq.rn = 1
LEFT JOIN bounty_counts b
  ON b.OwnerUserId = lq.OwnerUserId
LEFT JOIN user_tag_counts uc
  ON uc.Id = lq.OwnerUserId
LEFT JOIN duplicate_counts dc
  ON dc.question_id = lq.question_id
LEFT JOIN Users u
  ON u.Id = lq.OwnerUserId
WHERE ts.tag_rank <= 10
  AND (ts.question_count > 0 OR ts.avg_score IS NULL)
ORDER BY ts.question_count DESC, ts.tag_name;
