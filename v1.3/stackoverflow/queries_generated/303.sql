-- {"query": "303.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14300} 
WITH
  q_tags AS (
    SELECT
      q.Id AS question_id,
      lower(trim(t.tag)) AS tag,
      q.CreationDate AS question_created,
      q.Score AS question_score,
      COALESCE(q.ViewCount,0) AS view_count,
      q.AcceptedAnswerId,
      q.OwnerUserId
    FROM Posts q
    CROSS JOIN LATERAL regexp_split_to_table(substring(q.Tags, 2, length(q.Tags)-2), '><') AS t(tag)
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND q.Tags <> ''
  ),

  answers_info AS (
    SELECT
      a.Id AS answer_id,
      a.ParentId AS question_id,
      a.OwnerUserId AS answerer_id,
      a.Score AS answer_score,
      a.CreationDate AS answer_created,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) AS upvotes,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) AS downvotes,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS comments_count,
      CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END AS anon_answer
    FROM Posts a
    WHERE a.PostTypeId = 2
  ),

  question_answer_times AS (
    SELECT
      q.Id AS question_id,
      q.CreationDate AS question_created,
      q.AcceptedAnswerId,
      MIN(a.CreationDate) AS first_answer_date,
      (SELECT a2.CreationDate FROM Posts a2 WHERE a2.Id = q.AcceptedAnswerId LIMIT 1) AS accepted_answer_date,
      EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate))::double precision AS seconds_to_first_answer,
      EXTRACT(EPOCH FROM ((SELECT a2.CreationDate FROM Posts a2 WHERE a2.Id = q.AcceptedAnswerId LIMIT 1) - q.CreationDate))::double precision AS seconds_to_accepted_answer
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.CreationDate, q.AcceptedAnswerId
  ),

  tag_base AS (
    SELECT
      qt.tag,
      COUNT(DISTINCT qt.question_id) AS questions,
      SUM(qt.view_count)::bigint AS total_views,
      AVG(qt.question_score)::numeric(12,3) AS avg_question_score,
      AVG(qat.seconds_to_first_answer)::double precision AS avg_seconds_to_first_answer,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY qat.seconds_to_accepted_answer) FILTER (WHERE qat.seconds_to_accepted_answer IS NOT NULL) AS median_seconds_to_accepted,
      SUM(CASE WHEN qat.seconds_to_accepted_answer IS NOT NULL THEN 1 ELSE 0 END)::double precision AS accepted_count,
      COUNT(qt.question_id) AS total_count,
      SUM(CASE WHEN qt.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS anon_question_count,
      COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_links_count
    FROM q_tags qt
    LEFT JOIN question_answer_times qat ON qt.question_id = qat.question_id
    LEFT JOIN PostLinks pl ON pl.PostId = qt.question_id
    GROUP BY qt.tag
  ),

  tag_metrics AS (
    SELECT
      tag,
      questions,
      total_views,
      avg_question_score,
      avg_seconds_to_first_answer,
      median_seconds_to_accepted,
      accepted_count / NULLIF(total_count,0)::double precision AS frac_with_accepted_answer,
      anon_question_count,
      duplicate_links_count,
      PERCENT_RANK() OVER (ORDER BY total_views) AS view_percent_rank
    FROM tag_base
  ),

  top_answerers AS (
    SELECT
      qt.tag,
      ai.answerer_id,
      COUNT(*) AS answers_count,
      AVG(ai.answer_score)::numeric(8,3) AS avg_answer_score,
      SUM(ai.upvotes)::int AS total_upvotes,
      SUM(ai.comments_count)::int AS total_comments,
      RANK() OVER (PARTITION BY qt.tag ORDER BY COUNT(*) DESC, SUM(ai.upvotes) DESC) AS rnk
    FROM answers_info ai
    JOIN q_tags qt ON qt.question_id = ai.question_id
    WHERE ai.answerer_id IS NOT NULL
    GROUP BY qt.tag, ai.answerer_id
  ),

  top_answerers_top3 AS (
    SELECT *
    FROM top_answerers
    WHERE rnk <= 3
  ),

  badge_summary AS (
    SELECT
      b.UserId,
      COUNT(*) AS badges_total,
      SUM(CASE WHEN b.TagBased = 1 OR b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_badges,
      array_agg(DISTINCT b.Name) FILTER (WHERE b.TagBased = TRUE) AS tag_badge_names,
      MAX(b.Date) AS last_badge_date
    FROM Badges b
    GROUP BY b.UserId
  ),

  user_activity AS (
    SELECT
      u.Id AS user_id,
      u.Reputation,
      u.CreationDate AS user_created,
      u.DisplayName,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS posts_count,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
      COUNT(DISTINCT c.Id) AS comments_count,
      COALESCE(bs.tag_badges,0) AS tag_badges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN badge_summary bs ON bs.UserId = u.Id
    GROUP BY u.Id, bs.tag_badges, u.DisplayName, u.Reputation, u.CreationDate
  ),

  tag_top_answerers AS (
    SELECT
      ta.tag,
      ta.answerer_id,
      ua.DisplayName,
      ua.Reputation,
      ta.answers_count,
      ta.avg_answer_score,
      ta.total_upvotes,
      ta.rnk
    FROM top_answerers_top3 ta
    LEFT JOIN user_activity ua ON ua.user_id = ta.answerer_id
    ORDER BY ta.tag, ta.rnk
  ),

  top_by_views AS (
    SELECT tag, total_views, questions
    FROM tag_metrics
    ORDER BY total_views DESC NULLS LAST
    LIMIT 50
  ),

  top_by_engagement AS (
    SELECT tag, frac_with_accepted_answer, avg_seconds_to_first_answer
    FROM tag_metrics
    ORDER BY frac_with_accepted_answer DESC NULLS LAST
    LIMIT 50
  ),

  unioned_top AS (
    SELECT tag, total_views::double precision AS metric_value, 'views' AS metric_type FROM top_by_views
    UNION
    SELECT tag, frac_with_accepted_answer::double precision AS metric_value, 'accepted_frac' AS metric_type FROM top_by_engagement
  ),

  views_not_engagement AS (
    SELECT tag FROM top_by_views
    EXCEPT
    SELECT tag FROM top_by_engagement
  ),

  engagement_not_views AS (
    SELECT tag FROM top_by_engagement
    EXCEPT
    SELECT tag FROM top_by_views
  ),

  closed_counts AS (
    SELECT
      qt.tag,
      COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 10) AS closed_count,
      COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 11) AS reopened_count,
      COUNT(ph.Id) AS history_events
    FROM q_tags qt
    LEFT JOIN PostHistory ph ON ph.PostId = qt.question_id
    GROUP BY qt.tag
  )

SELECT
  tm.tag,
  tm.questions,
  tm.total_views,
  tm.avg_question_score,
  tm.frac_with_accepted_answer,
  CASE WHEN tm.avg_seconds_to_first_answer IS NULL THEN NULL ELSE make_interval(secs => tm.avg_seconds_to_first_answer) END AS avg_time_to_first_answer_interval,
  tm.median_seconds_to_accepted,
  tm.anon_question_count,
  tm.duplicate_links_count,
  tm.view_percent_rank,
  COALESCE(cc.closed_count,0) AS closed_count,
  COALESCE(cc.reopened_count,0) AS reopened_count,
  (SELECT string_agg(DISTINCT (COALESCE(tta.DisplayName,'<anon>') || ' (' || tta.answers_count || ' answers, ' || tta.total_upvotes || ' up)'), '; ' ORDER BY tta.rnk)
     FROM tag_top_answerers tta
     WHERE tta.tag = tm.tag
  ) AS top_answerers_summary,
  (SELECT COUNT(DISTINCT ai.answerer_id) FROM answers_info ai JOIN q_tags qt2 ON ai.question_id = qt2.question_id WHERE qt2.tag = tm.tag) AS distinct_answerers,
  (SELECT COALESCE(AVG(ai.answer_score),0) FROM answers_info ai JOIN q_tags qt3 ON ai.question_id = qt3.question_id WHERE qt3.tag = tm.tag) AS avg_answer_score_for_tag,
  (SELECT p.Title FROM Posts p JOIN q_tags qt4 ON p.Id = qt4.question_id WHERE qt4.tag = tm.tag ORDER BY qt4.view_count DESC LIMIT 1) AS top_question_title,
  (SELECT COUNT(*) FROM tag_top_answerers tta2 WHERE tta2.tag = tm.tag) AS top_answerers_count,
  CASE WHEN tm.total_views > 100000 THEN 'high-traffic' WHEN tm.total_views > 10000 THEN 'medium-traffic' ELSE 'low-traffic' END AS traffic_bucket,
  CASE WHEN EXISTS (SELECT 1 FROM views_not_engagement vne WHERE vne.tag = tm.tag) THEN 1 ELSE 0 END AS in_top_views_not_in_top_engagement,
  CASE WHEN EXISTS (SELECT 1 FROM engagement_not_views env WHERE env.tag = tm.tag) THEN 1 ELSE 0 END AS in_top_engagement_not_in_top_views,
  regexp_replace(tm.tag, '[^a-z0-9_-]', '', 'gi') AS sanitized_tag,
  (tm.total_views::double precision / NULLIF(tm.questions,0))::numeric(12,2) AS avg_views_per_question,
  (SELECT array_agg(ut.metric_type || '=' || to_char(ut.metric_value,'FM999999999.######')) FROM unioned_top ut WHERE ut.tag = tm.tag) AS unioned_metrics
FROM tag_metrics tm
LEFT JOIN closed_counts cc ON cc.tag = tm.tag
ORDER BY tm.total_views DESC NULLS LAST
LIMIT 200;