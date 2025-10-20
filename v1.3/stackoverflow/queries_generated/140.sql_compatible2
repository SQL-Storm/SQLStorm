WITH
recent_questions AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
    AND CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
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
-- replace regexp_split_to_table by standard SQL: split tags by parsing string using recursive CTE
tag_exploded AS (
  SELECT rq.Id AS QuestionId,
         lower(trim(both '<>' FROM part)) AS tag
  FROM recent_questions rq
  CROSS JOIN LATERAL (
    WITH RECURSIVE parts(pos, rest) AS (
      SELECT 1 AS pos,
             substring(rq.Tags FROM 2) || '' AS rest
      UNION ALL
      SELECT pos + 1,
             CASE
               WHEN position('><' IN rest) > 0 THEN substring(rest FROM position('><' IN rest) + 2)
               ELSE ''
             END
      FROM parts
      WHERE rest <> ''
    ),
    extracted AS (
      SELECT
        CASE
          WHEN position('><' IN rest) > 0 THEN substring(rest FROM 1 FOR position('><' IN rest)-1)
          ELSE rest
        END AS part,
        rest
      FROM parts
      WHERE rest <> ''
    )
    SELECT part
    FROM extracted
    WHERE part IS NOT NULL AND part <> ''
  ) AS derived(part)
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
         p.LastActivityDate,
         row_number() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn,
         rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS score_rank
  FROM Posts p
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '730 days'
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
         rq.LastEditorUserId,
         rq.FavoriteCount,
         (SELECT u.DisplayName FROM Users u WHERE u.Id = rq.LastEditorUserId) AS last_editor,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.Id AND c.CreationDate > rq.CreationDate) AS comments_after_creation,
         coalesce(rq.FavoriteCount, 0) AS favorites
  FROM recent_questions rq
  LEFT JOIN votes_agg v ON v.PostId = rq.Id
  LEFT JOIN answer_stats a ON a.question_id = rq.Id
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
  (SELECT string_agg(t.tag, ',' ORDER BY t.tag) FROM (SELECT DISTINCT tag FROM tag_exploded t WHERE t.QuestionId = c.question_id) t) AS all_tags,
  (SELECT u.DisplayName || ' (#' || u.Reputation || ')' FROM Users u WHERE u.Id = c.OwnerUserId) AS owner_label,
  CASE WHEN (c.upvotes + c.downvotes) = 0 THEN NULL ELSE round(100.0 * c.upvotes / NULLIF((c.upvotes + c.downvotes),0), 2) END AS pct_positive,
  CASE WHEN c.answers > 0 THEN round(CAST(c.favorites AS numeric) / NULLIF(c.answers,0), 3) ELSE NULL END AS favorite_per_answer,
  (SELECT a.Id FROM Posts a WHERE a.ParentId = c.question_id ORDER BY a.Score DESC, a.CreationDate ASC LIMIT 1) AS top_answer_id,
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
  AND (
        EXISTS (SELECT 1 FROM tag_exploded t WHERE t.QuestionId = c.question_id)
     OR c.answers > 0
     OR c.favorites > 0
  )
ORDER BY overall_rank
FETCH FIRST 100 ROWS ONLY;