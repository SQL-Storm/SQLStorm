-- {"query": "208.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6653} 
WITH tags_expanded AS (
  SELECT p.Id AS PostId, lower(trim(tg)) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><')) AS tg
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
), comments_recent AS (
  SELECT PostId,
    count(*) FILTER (WHERE CreationDate >= now() - interval '90 days') AS recent_comments,
    max(CreationDate) AS last_comment_date
  FROM Comments
  GROUP BY PostId
), accepted_per_user AS (
  SELECT a.OwnerUserId AS UserId, count(*) AS accepted_answers
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.AcceptedAnswerId = a.Id
  WHERE a.PostTypeId = 2
  GROUP BY a.OwnerUserId
), badge_counts AS (
  SELECT UserId,
    sum(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
    sum(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
    sum(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
  FROM Badges
  GROUP BY UserId
), user_agg AS (
  SELECT u.Id AS user_id, u.DisplayName,
    count(p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS total_posts,
    count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
    count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
    coalesce(avg(p.Score),0) AS avg_score,
    coalesce(apu.accepted_answers,0) AS accepted_answers,
    coalesce(bc.gold,0) AS gold, coalesce(bc.silver,0) AS silver, coalesce(bc.bronze,0) AS bronze,
    coalesce(sum(CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= now() - interval '30 days' THEN 1 ELSE 0 END),0) AS recent_answers
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN accepted_per_user apu ON apu.UserId = u.Id
  LEFT JOIN badge_counts bc ON bc.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, apu.accepted_answers, bc.gold, bc.silver, bc.bronze
), post_activity AS (
  SELECT q.Id AS question_id, q.Title, q.ViewCount, q.Score AS qscore, q.AnswerCount, q.CreationDate,
    coalesce(c.recent_comments,0) AS recent_comments,
    coalesce(pl.duplicate_count,0) AS duplicate_count,
    (q.Score * 3.0 + coalesce(q.ViewCount,0) * 0.1 + coalesce(q.AnswerCount,0) * 5.0 + coalesce(c.recent_comments,0) * 2.0 + coalesce(pl.duplicate_count,0) * -2.0) AS activity_score
  FROM Posts q
  LEFT JOIN comments_recent c ON c.PostId = q.Id
  LEFT JOIN (
    SELECT PostId AS pid, count(*) FILTER (WHERE LinkTypeId = 3) AS duplicate_count FROM PostLinks GROUP BY PostId
  ) pl ON pl.pid = q.Id
  WHERE q.PostTypeId = 1
), tag_stats AS (
  SELECT t.tag,
    count(distinct p.Id) AS question_count,
    avg(p.ViewCount) AS avg_views,
    avg(p.Score) AS avg_score,
    avg(coalesce(p.AnswerCount,0)) AS avg_answers,
    sum(CASE WHEN coalesce(p.AnswerCount,0) > 0 THEN 1 ELSE 0 END) AS questions_with_answers,
    (sum(CASE WHEN coalesce(p.AnswerCount,0) > 0 THEN 1 ELSE 0 END)::float / nullif(count(distinct p.Id),0)) AS pct_answered
  FROM tags_expanded t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.tag
), tag_user_contrib AS (
  SELECT te.tag, a.OwnerUserId AS user_id, count(*) AS answers_for_tag
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId
  JOIN tags_expanded te ON te.PostId = q.Id
  WHERE a.PostTypeId = 2
  GROUP BY te.tag, a.OwnerUserId
), tag_top_users AS (
  SELECT tag, user_id, answers_for_tag,
    rank() OVER (PARTITION BY tag ORDER BY answers_for_tag DESC, user_id) AS rnk
  FROM tag_user_contrib
), tag_featured_questions AS (
  SELECT te.tag, pa.question_id, pa.Title, pa.activity_score,
    row_number() OVER (PARTITION BY te.tag ORDER BY pa.activity_score DESC, pa.question_id) AS rn
  FROM tags_expanded te
  JOIN post_activity pa ON pa.question_id = te.PostId
), tag_duplicates AS (
  SELECT te.tag, count(distinct pl.Id) AS duplicate_links
  FROM tags_expanded te
  JOIN PostLinks pl ON (pl.PostId = te.PostId OR pl.RelatedPostId = te.PostId) AND pl.LinkTypeId = 3
  GROUP BY te.tag
), tag_summary AS (
  SELECT ts.tag, ts.question_count, ts.avg_views, ts.avg_score, ts.avg_answers, ts.pct_answered,
    coalesce(td.duplicate_links,0) AS duplicate_links,
    ttu.user_id AS top_user_id, ttu.answers_for_tag AS top_user_answers,
    u.DisplayName AS top_user_name,
    tfq.question_id AS featured_question_id, left(coalesce(tfq.Title,''),200) AS featured_question_title_snippet,
    tfq.activity_score,
    (CASE WHEN (SELECT avg(activity_score) FROM post_activity pa2 JOIN tags_expanded te2 ON pa2.question_id = te2.PostId WHERE te2.tag = ts.tag AND pa2.CreationDate >= now() - interval '30 days')
           > (SELECT avg(activity_score) FROM post_activity pa3 JOIN tags_expanded te3 ON pa3.question_id = te3.PostId WHERE te3.tag = ts.tag) * 1.5
     THEN true ELSE false END) AS trending
  FROM tag_stats ts
  LEFT JOIN tag_duplicates td ON td.tag = ts.tag
  LEFT JOIN (
    SELECT tag, user_id, answers_for_tag FROM tag_top_users WHERE rnk = 1
  ) ttu ON ttu.tag = ts.tag
  LEFT JOIN Users u ON u.Id = ttu.user_id
  LEFT JOIN (
    SELECT tag, question_id, Title, activity_score FROM tag_featured_questions WHERE rn = 1
  ) tfq ON tfq.tag = ts.tag
), untagged AS (
  SELECT '(untagged)' AS tag, count(*) AS question_count, avg(ViewCount) AS avg_views, avg(Score) AS avg_score, avg(coalesce(AnswerCount,0)) AS avg_answers,
    (sum(CASE WHEN coalesce(AnswerCount,0) > 0 THEN 1 ELSE 0 END)::float / nullif(count(*),0)) AS pct_answered,
    0 AS duplicate_links, null::int AS top_user_id, null::int AS top_user_answers, null::varchar AS top_user_name, null::int AS featured_question_id, null::varchar AS featured_question_title_snippet, 0.0 AS activity_score, false AS trending
  FROM Posts p WHERE p.PostTypeId = 1 AND (p.Tags IS NULL OR p.Tags = '')
), combined_tags AS (
  SELECT * FROM tag_summary
  UNION ALL
  SELECT * FROM untagged
), final_candidates AS (
  SELECT ct.*, coalesce(bc.gold,0) AS top_user_gold, coalesce(bc.silver,0) AS top_user_silver, coalesce(bc.bronze,0) AS top_user_bronze,
    (coalesce(ct.question_count,0) * 1.0 + coalesce(ct.avg_views,0) * 0.01 + coalesce(ct.avg_score,0) * 2.0 + coalesce(ct.top_user_answers,0) * 5.0 + (CASE WHEN ct.trending THEN 50 ELSE 0 END) - ct.duplicate_links * 3) AS composite_score
  FROM combined_tags ct
  LEFT JOIN badge_counts bc ON bc.UserId = ct.top_user_id
)
SELECT *
FROM final_candidates
INTERSECT
SELECT *
FROM final_candidates
WHERE question_count >= 1 AND composite_score IS NOT NULL
ORDER BY composite_score DESC NULLS LAST
LIMIT 200;