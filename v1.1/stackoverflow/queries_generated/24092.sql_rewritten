-- {"query": "24092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2988} 
WITH base_posts AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.Tags,
           p.OwnerUserId,
           p.CreationDate,
           CASE 
               WHEN p.Tags ILIKE '%<sql>%' AND p.Tags ILIKE '%<performance>%' THEN 'both'
               WHEN p.Tags ILIKE '%<sql>%' THEN 'sql'
               WHEN p.Tags ILIKE '%<performance>%' THEN 'performance'
               ELSE 'other'
           END AS tag_grp
    FROM Posts p
    WHERE p.PostTypeId = 1
),
sql_rnk AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Score DESC, CreationDate ASC) AS rn
    FROM base_posts
    WHERE tag_grp IN ('sql', 'both')
),
perf_rnk AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Score DESC, CreationDate ASC) AS rn
    FROM base_posts
    WHERE tag_grp IN ('performance', 'both')
),
latest_hist AS (
    SELECT ph.PostId,
           ph.Text
    FROM PostHistory ph
    JOIN (
        SELECT PostId,
               MAX(CreationDate) AS mx
        FROM PostHistory
        GROUP BY PostId
    ) mxq ON ph.PostId = mxq.PostId AND ph.CreationDate = mxq.mx
),
answers AS (
    SELECT ParentId,
           COUNT(*) AS ans_count
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
)
SELECT r.Id          AS qid,
       r.Title,
       r.Score,
       r.Tags,
       replace(replace(r.Tags, '<', ''), '>', '') AS tags_clean,
       u.Reputation,
       u.Location,
       lh.Text          AS latest_edit,
       a.ans_count,
       COALESCE(
         (SELECT COUNT(*)
          FROM Votes v
          WHERE v.PostId = r.Id
            AND v.VoteTypeId = 2
         ),0)                           AS upvote_cnt,
       CASE
           WHEN r.Score > 1000 THEN 'Supreme'
           WHEN r.Score BETWEEN 100 AND 999 THEN 'High'
           ELSE 'Low'
       END AS score_cat
FROM sql_rnk r
LEFT JOIN Users u ON u.Id = r.OwnerUserId
LEFT JOIN latest_hist lh ON lh.PostId = r.Id
LEFT JOIN answers a ON a.ParentId = r.Id
WHERE r.rn <= 10

UNION ALL

SELECT r.Id,
       r.Title,
       r.Score,
       r.Tags,
       replace(replace(r.Tags, '<', ''), '>', '') AS tags_clean,
       u.Reputation,
       u.Location,
       lh.Text          AS latest_edit,
       a.ans_count,
       COALESCE(
         (SELECT COUNT(*)
          FROM Votes v
          WHERE v.PostId = r.Id
            AND v.VoteTypeId = 2
         ),0)                           AS upvote_cnt,
       CASE
           WHEN r.Score > 1000 THEN 'Supreme'
           WHEN r.Score BETWEEN 100 AND 999 THEN 'High'
           ELSE 'Low'
       END AS score_cat
FROM perf_rnk r
LEFT JOIN Users u ON u.Id = r.OwnerUserId
LEFT JOIN latest_hist lh ON lh.PostId = r.Id
LEFT JOIN answers a ON a.ParentId = r.Id
WHERE r.rn <= 10

ORDER BY score_cat DESC, Score DESC
LIMIT 20;