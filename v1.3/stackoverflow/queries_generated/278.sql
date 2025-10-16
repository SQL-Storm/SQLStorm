-- {"query": "278.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4903} 
WITH
recent_q AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
    AND CreationDate >= now() - interval '3 years'
),
high AS (
  SELECT *
  FROM recent_q
  WHERE Score >= 50
  LIMIT 100
),
recent AS (
  SELECT *
  FROM recent_q
  WHERE Score < 50
  ORDER BY CreationDate DESC
  LIMIT 100
),
seed_posts AS (
  SELECT * FROM high
  UNION ALL
  SELECT * FROM recent
),
tag_exploded AS (
  SELECT sp.Id AS QuestionId,
         lower(trim(t.tag)) AS tag
  FROM seed_posts sp
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(sp.Tags, 2, char_length(coalesce(sp.Tags, '')) - 2), '><')) AS tag
  ) t
  WHERE sp.Tags IS NOT NULL AND sp.Tags <> ''
),
tag_pop AS (
  SELECT tag, count(*) AS tag_freq
  FROM tag_exploded
  GROUP BY tag
),
tags_agg AS (
  SELECT QuestionId,
         array_agg(distinct tag ORDER BY tag) AS tags_array,
         string_agg(distinct tag, ',' ORDER BY tag) AS tags_csv,
         count(*) AS tag_count
  FROM tag_exploded
  GROUP BY QuestionId
),
answers AS (
  SELECT a.ParentId AS QuestionId,
         count(*) AS answer_count,
         avg(a.Score) AS avg_answer_score,
         sum(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS answers_with_owner,
         min(a.CreationDate) AS first_answer_date,
         max(a.Score) AS best_score
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
top_answers AS (
  SELECT ParentId AS QuestionId, Id AS TopAnswerId, Score AS TopAnswerScore, Body AS TopAnswerBody, OwnerUserId AS TopAnswerOwner
  FROM (
    SELECT a.*,
           row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
  ) t
  WHERE rn = 1
),
vote_agg AS (
  SELECT v.PostId,
         count(*) AS vote_count,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         sum(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes,
         sum(CASE WHEN v.VoteTypeId IN (4,12) THEN 1 ELSE 0 END) AS flags_spam_offensive
  FROM Votes v
  GROUP BY v.PostId
),
comment_agg AS (
  SELECT c.PostId,
         count(*) AS comment_count,
         avg(char_length(c.Text)) AS avg_comment_len,
         max(c.CreationDate) AS last_comment_date
  FROM Comments c
  GROUP BY c.PostId
),
user_badges AS (
  SELECT b.UserId,
         count(*) AS badges_total,
         sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
         sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
         sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze
  FROM Badges b
  GROUP BY b.UserId
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         (extract(epoch FROM now() - u.CreationDate) / 86400)::int AS days_since_join,
         coalesce(b.badges_total, 0) AS badges_total,
         coalesce(b.gold, 0) AS gold,
         coalesce(b.silver, 0) AS silver,
         coalesce(b.bronze, 0) AS bronze
  FROM Users u
  LEFT JOIN user_badges b ON b.UserId = u.Id
),
link_counts AS (
  SELECT pl.PostId AS QuestionId,
         count(*) FILTER (WHERE pl.LinkTypeId = 1) AS links_out,
         count(*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicates,
         count(distinct pl.RelatedPostId) AS distinct_related
  FROM PostLinks pl
  GROUP BY pl.PostId
),
rev_agg AS (
  SELECT ph.PostId,
         (array_agg(ph.RevisionGUID ORDER BY ph.CreationDate DESC))[1:3] AS last3_guids,
         max(ph.CreationDate) AS last_edit
  FROM PostHistory ph
  GROUP BY ph.PostId
),
seed_stats AS (
  SELECT sp.*,
         row_number() OVER (ORDER BY sp.Score DESC NULLS LAST, sp.ViewCount DESC NULLS LAST) AS global_rank,
         rank() OVER (ORDER BY sp.Score DESC NULLS LAST) AS score_rank,
         ntile(10) OVER (ORDER BY sp.ViewCount DESC NULLS LAST) AS decile_by_views
  FROM seed_posts sp
),
suspicious_posts AS (
  SELECT Id
  FROM Posts
  WHERE Title ILIKE '%free%'
  EXCEPT
  SELECT Id FROM seed_posts
),
-- correlated heavy subquery example: count of high-rep answerers per question
high_rep_answerers AS (
  SELECT p.Id AS QuestionId,
         (SELECT count(DISTINCT a.OwnerUserId)
          FROM Posts a
          JOIN Users ua ON ua.Id = a.OwnerUserId
          WHERE a.PostTypeId = 2
            AND a.ParentId = p.Id
            AND ua.Reputation >= 10000) AS high_rep_answerer_count
  FROM seed_posts p
)
SELECT
  s.Id AS question_id,
  s.Title,
  substring(s.Body FROM 1 FOR 300) AS snippet_html,
  coalesce(t.tags_csv, '') AS tags,
  coalesce(t.tag_count, 0) AS tag_count,
  coalesce(btag.tag, '<<none>>') AS most_popular_tag_among_its_tags,
  coalesce(ans.answer_count, 0) AS answer_count,
  coalesce(ta.TopAnswerId, NULL) AS top_answer_id,
  coalesce(ta.TopAnswerScore, 0) AS top_answer_score,
  coalesce(v.vote_count, 0) AS total_votes,
  coalesce(v.upvotes, 0) AS upvotes,
  coalesce(v.downvotes, 0) AS downvotes,
  coalesce(c.comment_count, 0) AS comment_count,
  us.Reputation AS owner_reputation,
  us.days_since_join,
  coalesce(us.badges_total, 0) AS owner_badges,
  l.links_out,
  l.duplicates,
  l.distinct_related,
  r.last3_guids,
  r.last_edit,
  ans.first_answer_date,
  -- time to first answer in hours, NULL if none
  CASE WHEN ans.first_answer_date IS NOT NULL THEN extract(epoch FROM (ans.first_answer_date - s.CreationDate))/3600 ELSE NULL END AS hours_to_first_answer,
  -- time to accepted answer (if accepted)
  CASE WHEN s.AcceptedAnswerId IS NOT NULL
       THEN extract(epoch FROM ( (SELECT a.CreationDate FROM Posts a WHERE a.Id = s.AcceptedAnswerId) - s.CreationDate ))/3600
       ELSE NULL END AS hours_to_accepted_answer,
  -- complex ratio and score density with NULL logic
  CASE WHEN s.ViewCount > 0 THEN (s.Score::numeric / s.ViewCount)::numeric(10,6) ELSE NULL END AS score_to_view_ratio,
  -- composite quality score (arbitrary heavy expression)
  (COALESCE(s.Score,0) * 1.5
   + COALESCE(ans.answer_count,0) * 2
   + COALESCE(v.upvotes,0) * 0.8
   - COALESCE(v.downvotes,0) * 1.2
   + COALESCE(c.comment_count,0) * 0.3
   + greatest(coalesce(ta.TopAnswerScore,0),0) * 0.5
   + (case when s.AcceptedAnswerId is not null then 10 else 0 end)
   - (case when s.ClosedDate is not null then 50 else 0 end)
  )::numeric(12,4) AS heuristic_quality_score,
  s.global_rank,
  s.score_rank,
  s.decile_by_views,
  sr.high_rep_answerer_count,
  -- tags frequency vector sample: comma separated tag:freq pairs
  (SELECT string_agg(tp.tag || ':' || tp.tag_freq, ',' ORDER BY tp.tag_freq DESC NULLS LAST)
   FROM unnest(coalesce(t.tags_array, ARRAY[]::varchar[])) AS u(tag)
   LEFT JOIN tag_pop tp ON tp.tag = u.tag
  ) AS tag_freq_pairs,
  -- whether appears in suspicious set
  CASE WHEN s.Id IN (SELECT Id FROM suspicious_posts) THEN true ELSE false END AS flagged_title_contains_free,
  -- a synthetic hash-ish string composed of ids and dates for string-processing stress
  md5(coalesce(s.Title,'') || '|' || coalesce(s.OwnerDisplayName,'') || '|' || coalesce(s.CreationDate::text,'')) AS title_owner_hash
FROM seed_stats s
LEFT JOIN tags_agg t ON t.QuestionId = s.Id
LEFT JOIN LATERAL (
  SELECT tp.tag, tp.tag_freq
  FROM unnest(coalesce(t.tags_array, ARRAY[]::varchar[])) AS u(tag)
  JOIN tag_pop tp ON tp.tag = u.tag
  ORDER BY tp.tag_freq DESC NULLS LAST
  LIMIT 1
) btag ON TRUE
LEFT JOIN answers ans ON ans.QuestionId = s.Id
LEFT JOIN top_answers ta ON ta.QuestionId = s.Id
LEFT JOIN vote_agg v ON v.PostId = s.Id
LEFT JOIN comment_agg c ON c.PostId = s.Id
LEFT JOIN link_counts l ON l.QuestionId = s.Id
LEFT JOIN rev_agg r ON r.PostId = s.Id
LEFT JOIN user_stats us ON us.UserId = s.OwnerUserId
LEFT JOIN high_rep_answerers sr ON sr.QuestionId = s.Id
ORDER BY heuristic_quality_score DESC NULLS LAST, s.Score DESC NULLS LAST, s.CreationDate DESC
LIMIT 200;