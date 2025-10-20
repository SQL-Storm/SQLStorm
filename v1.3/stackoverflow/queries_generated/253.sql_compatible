WITH RECURSIVE linked_chain AS (
  SELECT pl.PostId,
         pl.RelatedPostId,
         1 AS depth,
         ARRAY[pl.PostId, pl.RelatedPostId] AS path
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1,3)
  UNION ALL
  SELECT lc.PostId,
         pl.RelatedPostId,
         lc.depth + 1,
         lc.path || ARRAY[pl.RelatedPostId]
  FROM linked_chain lc
  JOIN PostLinks pl ON pl.PostId = lc.RelatedPostId
  WHERE lc.depth < 4 AND NOT (pl.RelatedPostId = ANY(lc.path))
),
question_tags AS (
  SELECT p.Id AS question_id,
         p.Title,
         p.CreationDate,
         p.ViewCount,
         p.Score,
         p.AnswerCount,
         p.AcceptedAnswerId,
         p.OwnerUserId,
         trim(t.tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT regexp_split_to_table(coalesce(substring(p.Tags, 2, length(p.Tags)-2), ''), '><') AS tag
  ) t
  WHERE p.PostTypeId = 1
),
tag_aggregates AS (
  SELECT qt.tag,
         count(*) AS questions,
         sum(qt.AnswerCount) AS total_answers,
         avg(qt.ViewCount) AS avg_views,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY qt.ViewCount) AS median_views,
         max(qt.Score) AS max_score,
         sum(CASE WHEN qt.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_count
  FROM question_tags qt
  GROUP BY qt.tag
),
top_users_per_tag AS (
  SELECT tag,
         OwnerUserId AS user_id,
         count(*) AS q_count,
         row_number() OVER (PARTITION BY tag ORDER BY count(*) DESC, OwnerUserId) AS rn
  FROM question_tags
  WHERE OwnerUserId IS NOT NULL
  GROUP BY tag, OwnerUserId
),
recent_activity AS (
  SELECT p.Id AS post_id,
         p.PostTypeId,
         p.ParentId,
         p.OwnerUserId,
         p.CreationDate,
         p.LastActivityDate,
         CAST(floor(extract(epoch FROM (coalesce(p.LastActivityDate, p.CreationDate) - p.CreationDate))/3600) AS integer) AS hours_active,
         coalesce(u.Reputation,0) AS owner_rep,
         coalesce((SELECT count(*) FROM Comments c WHERE c.PostId = p.Id),0) AS comment_count,
         coalesce((SELECT count(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),0) AS upvotes
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
),
tag_medians AS (
  SELECT tag,
         (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY ViewCount)
          FROM Posts p2
          WHERE p2.Id IN (SELECT qt2.question_id FROM question_tags qt2 WHERE qt2.tag = qt.tag)
         ) AS median_view
  FROM (SELECT distinct tag FROM question_tags) qt
),
interesting_tags AS (
  SELECT ta.tag,
         ta.questions,
         ta.avg_views,
         ta.median_views,
         ta.max_score,
         tu.user_id AS top_user,
         tu.q_count AS top_user_qs
  FROM tag_aggregates ta
  LEFT JOIN top_users_per_tag tu ON tu.tag = ta.tag AND tu.rn = 1
  WHERE ta.questions > 100 AND ta.avg_views > 500
),
ru AS (
  SELECT q.tag,
         count(distinct ra.post_id) AS recent_questions_count,
         avg(ra.owner_rep) AS avg_owner_rep,
         avg(ra.upvotes) AS avg_upvotes
  FROM question_tags q
  LEFT JOIN recent_activity ra ON ra.post_id = q.question_id
  GROUP BY q.tag
),
set_a AS (SELECT tag FROM tag_aggregates WHERE questions > 100),
set_b AS (SELECT tag FROM tag_aggregates WHERE accepted_count < (questions/10) AND median_views > 1000),
set_c AS (SELECT tag FROM tag_aggregates WHERE max_score > 50)
SELECT it.tag,
       it.questions,
       it.avg_views,
       it.median_views,
       it.max_score,
       it.top_user,
       it.top_user_qs,
       coalesce(tm.median_view, it.median_views) AS post_median_view,
       lc.depth AS linked_depth,
       array_length(lc.path,1) AS link_path_len,
       coalesce(ru.recent_questions_count,0) AS recent_questions_count,
       coalesce(ru.avg_owner_rep,0) AS avg_owner_rep,
       coalesce(ru.avg_upvotes,0) AS avg_upvotes,
       concat(upper(left(it.tag,1)), lower(substring(it.tag from 2))) AS pretty_tag,
       CASE WHEN it.avg_views > 1000 THEN 'hot' WHEN it.avg_views > 500 THEN 'warm' ELSE 'cold' END AS heat,
       greatest(it.max_score,
                coalesce((SELECT max(Score) FROM Posts WHERE Id IN (SELECT question_id FROM question_tags WHERE tag = it.tag)),0)
       ) AS greatest_score,
       (SELECT round(100.0 * CAST(count(*) AS numeric) / nullif(it.questions,0),2)
        FROM question_tags q2
        WHERE q2.tag = it.tag AND lower(coalesce(q2.Title,'')) LIKE '%' || lower(it.tag) || '%'
       ) AS pct_title_contains_tag
FROM interesting_tags it
LEFT JOIN tag_medians tm ON tm.tag = it.tag
LEFT JOIN ru ON ru.tag = it.tag
LEFT JOIN LATERAL (
  SELECT lc.depth, lc.path
  FROM linked_chain lc
  WHERE lc.PostId IN (SELECT question_id FROM question_tags WHERE tag = it.tag LIMIT 1)
  ORDER BY lc.depth DESC
  LIMIT 1
) lc ON true
WHERE it.tag IN (
  (SELECT tag FROM set_a INTERSECT SELECT tag FROM set_c)
  EXCEPT
  SELECT tag FROM set_b
)
ORDER BY it.avg_views DESC, it.questions DESC
LIMIT 200;