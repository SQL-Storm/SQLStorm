-- {"query": "251.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3835} 
WITH
user_badges AS (
  SELECT UserId,
    SUM(CASE WHEN Class = 1 THEN 50 WHEN Class = 2 THEN 20 WHEN Class = 3 THEN 5 ELSE 1 END) AS badge_score,
    COUNT(*) AS badge_count
  FROM Badges
  GROUP BY UserId
),
tagged AS (
  SELECT p.Id AS question_id,
         trim(both ' ' FROM s.t) AS tag
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags,''), 2, GREATEST(length(coalesce(p.Tags,'')) - 2,0)), '><')) AS t
  ) s ON true
  WHERE p.PostTypeId = 1
),
answer_aggregates AS (
  SELECT q.Id AS question_id,
         COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS answer_count,
         AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS avg_answer_score,
         MAX(a.Score) FILTER (WHERE a.PostTypeId = 2) AS max_answer_score,
         SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS has_accepted
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),
accepted_info AS (
  SELECT q.Id AS question_id,
         a.Id AS accepted_answer_id,
         a.OwnerUserId AS accepted_owner_id,
         a.Score AS accepted_score,
         CASE WHEN a.CreationDate IS NOT NULL AND q.CreationDate IS NOT NULL
              THEN EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0
              ELSE NULL END AS hours_to_accept
  FROM Posts q
  LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
  WHERE q.PostTypeId = 1
),
last_comment AS (
  SELECT p.Id AS post_id,
         (SELECT c.Text FROM Comments c WHERE c.PostId = p.Id ORDER BY c.CreationDate DESC LIMIT 1) AS last_comment_text,
         (SELECT c.UserId FROM Comments c WHERE c.PostId = p.Id ORDER BY c.CreationDate DESC LIMIT 1) AS last_comment_userid,
         (SELECT c.CreationDate FROM Comments c WHERE c.PostId = p.Id ORDER BY c.CreationDate DESC LIMIT 1) AS last_comment_date
  FROM Posts p
  WHERE p.PostTypeId = 1
),
question_base AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         q.Tags,
         q.OwnerUserId,
         u.DisplayName AS owner_name,
         u.Reputation,
         COALESCE(ub.badge_score, 0) AS owner_badge_score,
         COALESCE(ag.answer_count, 0) AS computed_answer_count,
         COALESCE(ag.avg_answer_score, 0) AS avg_answer_score,
         COALESCE(ai.accepted_answer_id, -1) AS accepted_answer_id,
         ai.hours_to_accept,
         lc.last_comment_text,
         lc.last_comment_userid,
         lc.last_comment_date
  FROM Posts q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN user_badges ub ON u.Id = ub.UserId
  LEFT JOIN answer_aggregates ag ON q.Id = ag.question_id
  LEFT JOIN accepted_info ai ON q.Id = ai.question_id
  LEFT JOIN last_comment lc ON q.Id = lc.post_id
  WHERE q.PostTypeId = 1
),
scored AS (
  SELECT qb.*,
         GREATEST(EXTRACT(EPOCH FROM (current_timestamp - qb.CreationDate)) / 86400.0, 1.0) AS age_days,
         -- composite metric: weighted score, recency-adjusted views, answers, badges, favourites
         (qb.Score::double precision * 4.0
          + (qb.ViewCount::double precision / NULLIF(GREATEST(EXTRACT(EPOCH FROM (current_timestamp - qb.CreationDate)) / 86400.0,1.0),0.0)) * 0.2
          + qb.computed_answer_count * 6.0
          + qb.owner_badge_score * 0.5
          + COALESCE(qb.FavoriteCount,0) * 2.0) AS score_metric
  FROM question_base qb
),
tag_popularity AS (
  SELECT tag, COUNT(DISTINCT question_id) AS questions_with_tag, AVG(score_metric) AS avg_score_for_tag
  FROM scored s
  JOIN tagged t ON s.Id = t.question_id
  GROUP BY tag
),
ranked AS (
  SELECT s.*,
         ROW_NUMBER() OVER (ORDER BY s.score_metric DESC NULLS LAST) AS global_rank,
         RANK() OVER (PARTITION BY COALESCE(owner_name,'[unknown]') ORDER BY s.score_metric DESC NULLS LAST) AS owner_rank,
         PERCENT_RANK() OVER (ORDER BY s.score_metric) AS pct_rank
  FROM scored s
),
high_activity AS (
  SELECT r.Id, r.Title, r.owner_name, r.Reputation, r.score_metric, r.global_rank, r.owner_rank, r.pct_rank,
         r.computed_answer_count, r.avg_answer_score, r.accepted_answer_id, r.hours_to_accept, r.last_comment_text
  FROM ranked r
  WHERE r.score_metric > (SELECT COALESCE(avg(score_metric),0) * 1.5 FROM scored)
),
low_activity AS (
  SELECT r.Id, r.Title, r.owner_name, r.Reputation, r.score_metric, r.global_rank, r.owner_rank, r.pct_rank,
         r.computed_answer_count, r.avg_answer_score, r.accepted_answer_id, r.hours_to_accept, r.last_comment_text
  FROM ranked r
  WHERE r.score_metric <= (SELECT COALESCE(avg(score_metric),0) * 1.5 FROM scored)
),
combined AS (
  -- union of high and low activity but exclude purely anonymous questions (owner NULL) via EXCEPT
  SELECT * FROM high_activity
  UNION ALL
  SELECT * FROM low_activity
  EXCEPT
  SELECT * FROM (SELECT * FROM combined WHERE 1=0) AS noop -- placeholder to keep EXCEPT semantics consistent
),
filtered AS (
  -- Because the previous EXCEPT used a noop, simulate removal of rows with no owner with an anti-join
  SELECT c.*
  FROM (
    SELECT * FROM high_activity
    UNION ALL
    SELECT * FROM low_activity
  ) c
  WHERE c.owner_name IS NOT NULL
),
tagged_agg AS (
  SELECT f.*,
         (SELECT string_agg(tp.tag, ', ' ORDER BY tp.tag)
          FROM (
            SELECT DISTINCT t.tag
            FROM tagged t
            WHERE t.question_id = f.Id
            ORDER BY t.tag
          ) tp) AS tags_list,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.Id AND v.VoteTypeId = 2) AS upvotes_count,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.Id AND v.VoteTypeId = 3) AS downvotes_count,
         -- correlated subquery to find the top voter (user who cast the most upvotes on this post)
         (SELECT u.DisplayName FROM Users u WHERE u.Id = (
              SELECT v.UserId FROM Votes v WHERE v.PostId = f.Id AND v.UserId IS NOT NULL
              GROUP BY v.UserId ORDER BY COUNT(*) DESC, MAX(v.CreationDate) DESC LIMIT 1
          )) AS top_voter_name
  FROM filtered f
)
SELECT t.Id,
       t.Title,
       COALESCE(t.owner_name,'[deleted]') AS owner_name,
       t.Reputation AS owner_reputation,
       ROUND(t.score_metric::numeric,2) AS score_metric,
       t.global_rank,
       t.owner_rank,
       ROUND(t.pct_rank::numeric,4) AS pct_rank,
       t.computed_answer_count,
       ROUND(COALESCE(t.avg_answer_score,0)::numeric,2) AS avg_answer_score,
       CASE WHEN t.accepted_answer_id > 0 THEN t.hours_to_accept ELSE NULL END AS hours_to_accept,
       COALESCE(t.tags_list,'') AS tags,
       COALESCE(t.upvotes_count,0) AS upvotes,
       COALESCE(t.downvotes_count,0) AS downvotes,
       COALESCE(t.last_comment_text,'') AS last_comment_snippet,
       COALESCE(t.top_voter_name,'[anon]') AS top_voter,
       -- string expression to create a short summary
       LEFT(REGEXP_REPLACE(COALESCE(t.Title,''), E'\\s+', ' ', 'g') || ' [' || COALESCE(NULLIF(t.tags_list,''),'no-tags') || ']', 200) AS short_summary
FROM tagged_agg t
ORDER BY t.score_metric DESC NULLS LAST, t.global_rank
LIMIT 100;