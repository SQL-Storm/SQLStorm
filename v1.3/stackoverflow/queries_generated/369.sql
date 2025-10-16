-- {"query": "369.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19303} 
WITH
posts_with_tags AS (
  SELECT
    p.Id AS post_id,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    LOWER(TRIM(t.tag)) AS tag
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
  ) t ON p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
),
tag_stats AS (
  SELECT
    tag,
    count(*) FILTER (WHERE PostTypeId = 1) AS question_count,
    count(*) FILTER (WHERE PostTypeId = 2) AS answer_count,
    AVG(Score) FILTER (WHERE PostTypeId = 1) AS avg_question_score,
    AVG(Score) AS avg_overall_score,
    SUM(COALESCE(ViewCount,0)) FILTER (WHERE PostTypeId = 1) AS total_views,
    MAX(Score) FILTER (WHERE PostTypeId = 1) AS top_question_score,
    MIN(Score) FILTER (WHERE PostTypeId = 1) AS bottom_question_score
  FROM posts_with_tags
  WHERE tag IS NOT NULL
  GROUP BY tag
),
vote_weights AS (
  SELECT
    v.PostId,
    SUM(
      (CASE v.VoteTypeId
        WHEN 1 THEN 8.0
        WHEN 2 THEN 1.0
        WHEN 3 THEN -1.5
        WHEN 4 THEN -3.0
        WHEN 5 THEN 0.5
        WHEN 8 THEN 2.0
        WHEN 9 THEN 2.0
        ELSE 0.0 END)
      * GREATEST(0.1, 1 - LEAST(3650, EXTRACT(EPOCH FROM (current_timestamp - v.CreationDate)) / 86400) / 3650.0)
    ) AS weighted_votes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    MAX(v.CreationDate) AS last_vote_date
  FROM Votes v
  GROUP BY v.PostId
),
post_history_stats AS (
  SELECT
    ph.PostId,
    COUNT(*) AS history_count,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,24) THEN 1 ELSE 0 END) AS edit_events,
    COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS distinct_editors,
    MIN(ph.CreationDate) AS first_history,
    MAX(ph.CreationDate) AS last_history
  FROM PostHistory ph
  GROUP BY ph.PostId
),
comment_stats AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    AVG(length(c.Text)) AS avg_comment_len,
    SUM(length(COALESCE(c.Text,'')) - length(replace(COALESCE(c.Text,''), '?', ''))) AS question_mark_count,
    SUM(length(COALESCE(c.Text,'')) - length(replace(COALESCE(c.Text,''), '!', ''))) AS exclamation_count,
    SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS anonymous_comments
  FROM Comments c
  GROUP BY c.PostId
),
problem_posts AS (
  (SELECT p.Id FROM Posts p WHERE p.PostTypeId IN (1,2) AND COALESCE(p.Score,0) < 0)
  UNION
  (SELECT p.Id FROM Posts p WHERE p.PostTypeId = 1 AND COALESCE(p.ViewCount,0) < 5)
  EXCEPT
  (SELECT p.Id FROM Posts p WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0)
),
recent_small_posts AS (
  (SELECT Id, OwnerUserId, Score, ViewCount, Title FROM Posts WHERE PostTypeId = 1 AND COALESCE(Score,0) BETWEEN -5 AND 5)
  UNION
  (SELECT Id, OwnerUserId, Score, ViewCount, Title FROM Posts WHERE PostTypeId = 2 AND COALESCE(Score,0) BETWEEN -3 AND 3)
  INTERSECT
  (SELECT Id, OwnerUserId, Score, ViewCount, Title FROM Posts WHERE CreationDate > current_timestamp - interval '30 days')
),
accepted_answer_ids AS (
  SELECT DISTINCT AcceptedAnswerId AS answer_id FROM Posts WHERE AcceptedAnswerId IS NOT NULL
),
answers_ranked AS (
  SELECT
    q.Id AS question_id,
    a.Id AS answer_id,
    a.OwnerUserId AS answerer_id,
    a.Score AS answer_score,
    a.CreationDate AS answer_creation,
    ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rn
  FROM Posts q
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
),
top_answerers AS (
  SELECT question_id, answer_id, answerer_id, answer_score
  FROM answers_ranked
  WHERE rn = 1
),
top_tags_agg AS (
  SELECT p.OwnerUserId AS user_id, LOWER(TRIM(t.tag)) AS tag, COUNT(*) AS cnt
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(COALESCE(p.Tags,''), 2, length(COALESCE(p.Tags,'')) - 2), '><')) AS tag
  ) t ON p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId, LOWER(TRIM(t.tag))
),
top_tags_per_user AS (
  SELECT user_id, tag, cnt, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY cnt DESC, tag) AS rnk
  FROM top_tags_agg
),
user_top_tags AS (
  SELECT user_id, tag FROM top_tags_per_user WHERE rnk = 1
),
user_badge_counts AS (
  SELECT
    b.UserId AS user_id,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
top_posts_per_user AS (
  SELECT
    p.OwnerUserId AS user_id,
    p.Id AS post_id,
    p.PostTypeId,
    p.Title,
    p.Score,
    COALESCE(vs.weighted_votes,0) AS weighted_votes,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COALESCE(vs.weighted_votes,0) DESC, p.Score DESC, p.CreationDate ASC) AS rnk
  FROM Posts p
  LEFT JOIN vote_weights vs ON vs.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL
),
user_top_post AS (
  SELECT user_id, post_id, PostTypeId, Title, Score, weighted_votes FROM top_posts_per_user WHERE rnk = 1
),
user_post_aggregates AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_posted,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_posted,
    COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)),0) AS avg_post_score,
    COALESCE(SUM(COALESCE(vs.weighted_votes, 0)),0) AS total_weighted_votes,
    COALESCE(MAX(p.Score), 0) AS user_max_score,
    COALESCE(SUM(CASE WHEN aaid.answer_id IS NOT NULL THEN 1 ELSE 0 END),0) AS accepted_answers_count,
    COALESCE(COUNT(DISTINCT COALESCE(LOWER(TRIM(t.tag)), '(none)')), 0) AS distinct_tags_used
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN vote_weights vs ON vs.PostId = p.Id
  LEFT JOIN accepted_answer_ids aaid ON aaid.answer_id = p.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(COALESCE(p.Tags,''), 2, length(COALESCE(p.Tags,'')) - 2), '><')) AS tag
  ) t ON p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
user_ranked AS (
  SELECT
    upa.*,
    COALESCE(ubc.gold,0) AS gold,
    COALESCE(ubc.silver,0) AS silver,
    COALESCE(ubc.bronze,0) AS bronze,
    utt.tag AS top_tag,
    utp.post_id AS top_post_id,
    utp.title AS top_post_title,
    ROW_NUMBER() OVER (ORDER BY (COALESCE(upa.total_weighted_votes,0) * 0.5 + COALESCE(upa.avg_post_score,0) * 2 + COALESCE(ubc.gold,0) * 10 + COALESCE(upa.answers_posted,0) * 0.3 + COALESCE(upa.questions_posted,0) * 0.1 + COALESCE(upa.distinct_tags_used,0) * 0.05) DESC) AS composite_rank
  FROM user_post_aggregates upa
  LEFT JOIN user_badge_counts ubc ON ubc.user_id = upa.user_id
  LEFT JOIN user_top_tags utt ON utt.user_id = upa.user_id
  LEFT JOIN user_top_post utp ON utp.user_id = upa.user_id
)
SELECT
  ur.composite_rank,
  ur.user_id,
  ur.displayname,
  ur.reputation,
  ur.questions_posted,
  ur.answers_posted,
  ur.avg_post_score,
  ur.user_max_score,
  ur.total_weighted_votes,
  ur.accepted_answers_count,
  ur.distinct_tags_used,
  ur.gold,
  ur.silver,
  ur.bronze,
  COALESCE(ur.top_tag, '(none)') AS favorite_tag,
  ur.top_post_id,
  COALESCE(ur.top_post_title, '(untitled)') AS top_post_title,
  (SELECT b.Name FROM Badges b WHERE b.UserId = ur.user_id ORDER BY b.Date DESC LIMIT 1) AS last_badge_name,
  COALESCE(ROUND(100.0 * ur.accepted_answers_count / NULLIF(ur.answers_posted,0),2), 0.0) AS pct_answers_accepted,
  (SELECT
      ROUND(AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)))::numeric / 3600.0,2)
    FROM Posts q
    JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.OwnerUserId = ur.user_id AND q.AcceptedAnswerId IS NOT NULL
  ) AS avg_hours_to_accept,
  (SELECT COUNT(*) FROM problem_posts pp JOIN Posts p2 ON p2.Id = pp.Id WHERE p2.OwnerUserId = ur.user_id) AS problem_posts_owned,
  CASE
    WHEN ur.questions_posted IS NULL AND ur.answers_posted IS NULL THEN '(no posts)'
    WHEN COALESCE(ur.questions_posted,0) = 0 AND COALESCE(ur.answers_posted,0) = 0 THEN '(no posts)'
    ELSE concat(
      COALESCE(ur.questions_posted,0)::text, 'Q/', COALESCE(ur.answers_posted,0)::text, 'A; ',
      COALESCE(ur.distinct_tags_used,0)::text, ' tags; score=', COALESCE(ur.avg_post_score,0)::text
    )
  END AS quick_summary,
  CASE WHEN POSITION('sql' IN LOWER(COALESCE((SELECT u.AboutMe FROM Users u WHERE u.Id = ur.user_id),''))) > 0 THEN true ELSE false END AS mentions_sql,
  CASE WHEN POSITION('performance' IN LOWER(COALESCE((SELECT u.AboutMe FROM Users u WHERE u.Id = ur.user_id),''))) > 0 THEN true ELSE false END AS mentions_performance,
  (SELECT ts.avg_question_score FROM tag_stats ts WHERE ts.tag = ur.top_tag LIMIT 1) AS top_tag_avg_question_score,
  (SELECT ts.question_count FROM tag_stats ts WHERE ts.tag = ur.top_tag LIMIT 1) AS top_tag_question_count,
  (SELECT COUNT(*) FROM recent_small_posts rsp WHERE rsp.OwnerUserId = ur.user_id) AS recent_small_posts_count
FROM user_ranked ur
ORDER BY ur.composite_rank
LIMIT 50;