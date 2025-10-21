-- {"query": "24009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4916} 

WITH
  -- Base questions with some aggregation and a window function
  q AS (
    SELECT p.id,
           p.title,
           p.score,
           p.viewcount,
           p.owneruserid,
           p.tags,
           p.creationdate,
           COALESCE((
              SELECT COUNT(*) FROM Votes v
              WHERE v.postid = p.id AND v.votetypeid = 2
           ),0) AS upvotes,
           COALESCE((
              SELECT COUNT(*) FROM Votes v
              WHERE v.postid = p.id AND v.votetypeid = 3
           ),0) AS downvotes,
           ROW_NUMBER() OVER (ORDER BY p.score DESC, p.lastactivitydate DESC) AS rn
    FROM Posts p
    WHERE p.posttypeid = 1
  ),
  -- Tags extracted from the tags column and from edit history (set operator)
  tags AS (
    SELECT q.id AS post_id,
           tag
    FROM q
    JOIN LATERAL unnest(string_to_array(replace(replace(q.tags, '<', ''), '>', ''), ' ')) AS tag
    UNION ALL
    SELECT ph.postid AS post_id,
           ph.text AS tag
    FROM PostHistory ph
    WHERE ph.posthistorytypeid IN (1,2,3)          -- initial title/body/tags
  ),
  -- Duplicate link count
  dup AS (
    SELECT pl.postid,
           COUNT(DISTINCT pl.relatedpostid) AS dup_count
    FROM PostLinks pl
    WHERE pl.linktypeid = 3
    GROUP BY pl.postid
  ),
  -- Final result with complex predicates and NULL handling
  final AS (
    SELECT q.id,
           q.title,
           q.score,
           q.viewcount,
           q.owneruserid,
           q.rn,
           q.upvotes,
           q.downvotes,
           COALESCE(d.dup_count,0) AS duplicate_count,
           STRING_AGG(tags.tag, ', ') AS tags_list,
           CASE
             WHEN q.score - q.downvotes > 200 THEN 'High'
             WHEN q.score - q.downvotes > 0   THEN 'Medium'
             ELSE 'Low'
           END AS score_category
    FROM q
    LEFT JOIN dup d ON d.postid = q.id
    LEFT JOIN tags ON tags.post_id = q.id
    GROUP BY q.id, q.title, q.score, q.viewcount, q.owneruserid, q.rn, q.upvotes, q.downvotes, d.dup_count
  )
SELECT *
FROM final
WHERE rn <= 500
ORDER BY rn;
