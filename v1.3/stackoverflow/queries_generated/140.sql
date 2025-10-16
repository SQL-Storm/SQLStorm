-- {"query": "140.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 3031} 
WITH
recent_questions AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
    AND CreationDate > now() - interval '365 days'
),
answers AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
),
user_badges AS (
  SELECT UserId, COUNT(*) AS badges, SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold
  FROM Badges
  GROUP BY UserId
),
-- explode tags like '<tag1><tag2>' into rows (Post.Tags assumed form '<t1><t2>')
tag_exploded AS (
  SELECT rq.Id AS QuestionId,
         lower(trim(both '<>' FROM t)) AS tag
  FROM recent_questions rq
  CROSS JOIN LATERAL regexp_split_to_table(
    substring(rq.Tags, 2, greatest(length(rq.Tags) - 2, 0)),
    '><'
  ) AS t
),
tag_counts AS (
  SELECT tag, COUNT(DISTINCT QuestionId) AS qcount
  FROM tag_exploded
  GROUP BY tag
),
answer_stats AS (
  SELECT a.ParentId AS question_id,
         COUNT(*) AS answers,
         AVG(a.Score) AS avg_ans_score,
         MAX(a.Score) AS max_ans_score
  FROM answers a
  JOIN recent_questions rq ON a.ParentId = rq.Id
  GROUP BY a.ParentId
),
activity_rank AS (
  SELECT p.Id,
         p.PostTypeId,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST) AS rn,
         rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS score_rank
  FROM Posts p
  WHERE p.CreationDate > now() - interval '730 days'
),
top_contributors AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         coalesce(b.badges,0) AS badges,
         coalesce(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS questions_posted
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
  LEFT JOIN user_badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, b.badges
  HAVING coalesce(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) > 0
  ORDER BY Reputation DESC
  LIMIT 50
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
links_agg AS (
  SELECT pl.PostId,
         COUNT(*) AS links_to,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicates_to
  FROM PostLinks pl
  GROUP BY pl.PostId
),
complex AS (
  SELECT rq.Id                    AS question_id,
         rq.Title,
         coalesce(v.upvotes,0)     AS upvotes,
         coalesce(v.downvotes,0)   AS downvotes,
         coalesce(a.answers,0)     AS answers,
         coalesce(tc.qcount,0)     AS tag_popularity,
         coalesce(ub.badges,0)     AS user_badges,
         coalesce(ub.gold,0)       AS user_gold,
         coalesce(links_agg.links_to,0)      AS links_to,
         coalesce(links_agg.duplicates_to,0) AS duplicates_to,
         rq.CreationDate,
         rq.OwnerUserId,
         rq.Score,
         (SELECT u.DisplayName FROM Users u WHERE u.Id = rq.LastEditorUserId) AS last_editor,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id AND c.CreationDate > rq.CreationDate) AS comments_after_creation,
         coalesce(rq.FavoriteCount, 0) AS favorites
  FROM recent_questions rq
  LEFT JOIN votes_agg v ON v.PostId = rq.Id
  LEFT JOIN answer_stats a ON a.question_id = rq.Id
  -- pick the lexicographically first tag for quick tag_popularity join
  LEFT JOIN tag_counts tc ON tc.tag = (
    SELECT te.tag
    FROM tag_exploded te
    WHERE te.QuestionId = rq.Id
    ORDER BY te.tag
    LIMIT 1
  )
  LEFT JOIN user_badges ub ON ub.UserId = rq.OwnerUserId
  LEFT JOIN links_agg ON links_agg.PostId = rq.Id
)
SELECT
  c.question_id,
  left(coalesce(c.Title,''), 200) AS title_snippet,
  c.Score,
  c.upvotes,
  c.downvotes,
  c.answers,
  c.tag_popularity,
  c.user_badges,
  c.user_gold,
  c.links_to,
  c.duplicates_to,
  c.favorites,
  row_number() OVER (ORDER BY (c.upvotes - c.downvotes) DESC, c.Score DESC, c.answers DESC) AS overall_rank,
  dense_rank() OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate DESC) AS recent_for_owner,
  -- list all tags for the question, comma-separated
  (SELECT string_agg(distinct t.tag, ',' ORDER BY t.tag) FROM tag_exploded t WHERE t.QuestionId = c.question_id) AS all_tags,
  -- owner label with fallback to 'anonymous'
  (SELECT u.DisplayName || ' (#' || u.Reputation || ')' FROM Users u WHERE u.Id = c.OwnerUserId) AS owner_label,
  -- percent positive votes with NULL logic and rounding
  CASE WHEN (c.upvotes + c.downvotes) = 0 THEN NULL ELSE round(100.0 * c.upvotes / NULLIF(c.upvotes + c.downvotes,0), 2) END AS pct_positive,
  -- favorites per answer (null if no answers)
  CASE WHEN c.answers > 0 THEN round((c.favorites::numeric) / NULLIF(c.answers,0), 3) ELSE NULL END AS favorite_per_answer,
  -- correlated subquery: best answer id by score for this question (if any)
  (SELECT a.Id FROM Posts a WHERE a.ParentId = c.question_id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC LIMIT 1) AS top_answer_id,
  -- correlated subquery: highest upvoted voter for the question (if Votes stores UserId)
  (SELECT v.UserId
   FROM Votes v
   WHERE v.PostId = c.question_id AND v.VoteTypeId = 2 AND v.UserId IS NOT NULL
   GROUP BY v.UserId
   ORDER BY COUNT(*) DESC, MAX(v.CreationDate) DESC
   LIMIT 1) AS most_active_upvoter
FROM complex c
WHERE c.Score >= (
        SELECT percentile_cont(0.10) WITHIN GROUP (ORDER BY Score)
        FROM Posts
        WHERE PostTypeId = 1
      )
  AND (c.upvotes - c.downvotes) >= 0
  -- require at least one tag OR at least one answer OR > 0 favorites to stress predicate diversity
  AND (
        EXISTS (SELECT 1 FROM tag_exploded t WHERE t.QuestionId = c.question_id)
     OR c.answers > 0
     OR c.favorites > 0
  )
ORDER BY overall_rank
FETCH FIRST 100 ROWS ONLY;