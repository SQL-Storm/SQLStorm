-- {"query": "318.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22720} 
WITH
base_questions AS (
  SELECT
    p.Id AS question_id,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    COALESCE(p.Tags,'') AS Tags,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.FavoriteCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
question_tags AS (
  SELECT
    q.question_id,
    lower(trim(t.tag)) AS tag
  FROM base_questions q
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, GREATEST(length(q.Tags) - 2, 0)), '><')) AS t(tag)
  WHERE q.Tags IS NOT NULL AND q.Tags <> '' AND t.tag IS NOT NULL AND t.tag <> ''
),
answers_agg AS (
  SELECT
    a.ParentId AS question_id,
    COUNT(*) AS answer_count,
    AVG(COALESCE(a.Score,0))::numeric AS avg_answer_score,
    MAX(COALESCE(a.Score,0)) AS max_answer_score,
    COUNT(*) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS answers_with_owner
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
votes_agg AS (
  SELECT
    v.PostId,
    COUNT(*) AS total_votes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes_count,
    SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS total_bounty
  FROM Votes v
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    COUNT(DISTINCT COALESCE(c.UserId,-1)) AS distinct_commenters,
    MAX(c.CreationDate) AS last_comment_date
  FROM Comments c
  GROUP BY c.PostId
),
top_commenters AS (
  SELECT PostId, UserId AS top_commenter_id
  FROM (
    SELECT c.PostId, c.UserId, COUNT(*) AS cnt,
           ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY COUNT(*) DESC) AS rn
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.PostId, c.UserId
  ) x
  WHERE rn = 1
),
history_agg AS (
  SELECT
    ph.PostId,
    COUNT(*) AS history_count,
    SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS body_edits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS title_edits,
    MAX(ph.CreationDate) AS last_history_date,
    COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS distinct_editors
  FROM PostHistory ph
  GROUP BY ph.PostId
),
links_agg AS (
  SELECT
    pl.PostId,
    COUNT(*) AS link_count,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_out_count,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_out_count,
    COUNT(DISTINCT pl.RelatedPostId) AS distinct_linked_posts
  FROM PostLinks pl
  GROUP BY pl.PostId
),
badges_agg AS (
  SELECT
    b.UserId,
    COUNT(*) AS badge_count,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    COUNT(DISTINCT b.Name) AS distinct_badge_names
  FROM Badges b
  GROUP BY b.UserId
),
user_activity AS (
  SELECT
    u.Id AS user_id,
    u.Reputation,
    u.CreationDate AS user_created,
    u.LastAccessDate,
    u.Views AS profile_views,
    COALESCE(badges_agg.badge_count,0) AS badge_count,
    COALESCE(badges_agg.gold_badges,0) AS gold_badges,
    COALESCE(badges_agg.silver_badges,0) AS silver_badges,
    COALESCE(badges_agg.bronze_badges,0) AS bronze_badges,
    COALESCE(q_counts.questions_posted,0) AS questions_posted,
    COALESCE(a_counts.answers_posted,0) AS answers_posted,
    COALESCE(q_view_sum.total_question_views,0) AS total_question_views
  FROM Users u
  LEFT JOIN badges_agg ON badges_agg.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS questions_posted
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) q_counts ON q_counts.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS answers_posted
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) a_counts ON a_counts.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, SUM(COALESCE(ViewCount,0)) AS total_question_views
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) q_view_sum ON q_view_sum.OwnerUserId = u.Id
),
tag_level_stats AS (
  SELECT
    qt.tag,
    COUNT(DISTINCT qt.question_id) AS tag_question_count,
    AVG(COALESCE(bq.Score,0))::numeric AS avg_question_score,
    AVG(COALESCE(bq.ViewCount,0))::numeric AS avg_question_views,
    AVG(COALESCE(a.avg_answer_score,0))::numeric AS avg_answer_score_per_tag,
    MAX(COALESCE(bq.Score,0)) AS max_question_score,
    SUM(COALESCE(bq.ViewCount,0)) AS total_views
  FROM question_tags qt
  JOIN base_questions bq ON bq.question_id = qt.question_id
  LEFT JOIN answers_agg a ON a.question_id = bq.question_id
  GROUP BY qt.tag
),
scored_posts AS (
  SELECT
    bq.question_id,
    bq.Title,
    bq.OwnerUserId,
    bq.OwnerDisplayName,
    bq.CreationDate,
    bq.LastActivityDate,
    COALESCE(bq.Score,0) AS score,
    COALESCE(bq.ViewCount,0) AS viewcount,
    COALESCE(answers_agg.answer_count,0) AS answer_count,
    COALESCE(answers_agg.avg_answer_score,0) AS avg_answer_score,
    COALESCE(votes_agg.upvotes,0) AS upvotes,
    COALESCE(votes_agg.downvotes,0) AS downvotes,
    COALESCE(votes_agg.total_votes,0) AS total_votes,
    COALESCE(comments_agg.comment_count,0) AS comment_count,
    COALESCE(comments_agg.distinct_commenters,0) AS distinct_commenters,
    top_commenters.top_commenter_id,
    COALESCE(history_agg.history_count,0) AS history_count,
    COALESCE(links_agg.link_count,0) AS link_count,
    COALESCE(links_agg.duplicate_out_count,0) AS duplicate_out_count,
    COALESCE(user_activity.reputation,0) AS owner_reputation,
    COALESCE(user_activity.badge_count,0) AS owner_badge_count,
    COALESCE(bq.FavoriteCount,0) AS favorite_count,
    GREATEST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - bq.CreationDate))/86400.0, 0) AS age_days,
    EXP(-GREATEST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - bq.CreationDate))/86400.0, 0) / 365.0) AS recency_weight,
    LN(GREATEST(bq.ViewCount, 1)) AS log_views,
    (
      (COALESCE(bq.Score,0)::numeric * 3.0)
      + (COALESCE(votes_agg.upvotes,0) * 1.0) - (COALESCE(votes_agg.downvotes,0) * 1.5)
      + (COALESCE(answers_agg.answer_count,0) * 2.0)
      + (COALESCE(answers_agg.avg_answer_score,0) * 1.8)
      + (LN(GREATEST(bq.ViewCount,1)) * 0.9) * EXP(-GREATEST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - bq.CreationDate))/86400.0, 0) / 365.0)
      + (COALESCE(comments_agg.comment_count,0) * 1.2)
      + (COALESCE(bq.FavoriteCount,0) * 2.5)
      + (COALESCE(user_activity.reputation,0) / GREATEST(NULLIF((COALESCE(user_activity.questions_posted,0) + COALESCE(user_activity.answers_posted,0)),0),1) * 0.0005)
      + (COALESCE(user_activity.badge_count,0) * 0.7)
      - (COALESCE(history_agg.history_count,0) * 0.3)
      - (COALESCE(links_agg.duplicate_out_count,0) * 5)
      + CASE WHEN bq.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END
    ) AS composite_score
  FROM base_questions bq
  LEFT JOIN answers_agg ON answers_agg.question_id = bq.question_id
  LEFT JOIN votes_agg ON votes_agg.PostId = bq.question_id
  LEFT JOIN comments_agg ON comments_agg.PostId = bq.question_id
  LEFT JOIN top_commenters ON top_commenters.PostId = bq.question_id
  LEFT JOIN history_agg ON history_agg.PostId = bq.question_id
  LEFT JOIN links_agg ON links_agg.PostId = bq.question_id
  LEFT JOIN user_activity ON user_activity.user_id = bq.OwnerUserId
),
ranked_per_tag AS (
  SELECT
    qt.tag,
    sp.*,
    COALESCE(substring(regexp_replace(sp.Title, '<[^>]+>', '', 'g'),1,160), '') ||
      CASE WHEN length(COALESCE(sp.Title,'')) > 160 THEN '...' ELSE '' END AS title_snippet,
    ROW_NUMBER() OVER (PARTITION BY qt.tag ORDER BY sp.composite_score DESC NULLS LAST, sp.viewcount DESC) AS rn,
    RANK() OVER (PARTITION BY qt.tag ORDER BY sp.composite_score DESC NULLS LAST) AS rnk,
    tls.avg_question_views,
    tls.tag_question_count,
    (sp.composite_score - COALESCE(tls.avg_question_score, 0))
      / GREATEST(
          COALESCE((
            SELECT STDDEV_POP(COALESCE(bq.Score,0)) FROM base_questions bq
            JOIN question_tags qt2 ON bq.question_id = qt2.question_id
            WHERE qt2.tag = qt.tag
          ), 0),
          1
        ) AS z_score_within_tag
  FROM question_tags qt
  JOIN scored_posts sp ON sp.question_id = qt.question_id
  LEFT JOIN tag_level_stats tls ON tls.tag = qt.tag
),
top_per_tag_set AS (
  SELECT tag, question_id, title_snippet AS title, OwnerUserId AS owner_id, composite_score, viewcount, age_days, rn, rnk, avg_question_views, tag_question_count, z_score_within_tag
  FROM ranked_per_tag
  WHERE rn <= 5
),
unseen_gems AS (
  SELECT DISTINCT
    qt.tag,
    sp.question_id,
    substring(regexp_replace(sp.Title, '<[^>]+>', '', 'g'),1,160) ||
      CASE WHEN length(COALESCE(sp.Title,'')) > 160 THEN '...' ELSE '' END AS title,
    sp.OwnerUserId AS owner_id,
    sp.composite_score,
    sp.viewcount,
    sp.age_days,
    NULL::int AS rn,
    NULL::int AS rnk,
    tls.avg_question_views,
    tls.tag_question_count,
    NULL::numeric AS z_score_within_tag
  FROM scored_posts sp
  JOIN question_tags qt ON qt.question_id = sp.question_id
  LEFT JOIN tag_level_stats tls ON tls.tag = qt.tag
  WHERE sp.composite_score > COALESCE(tls.avg_question_score, 0) * 1.2
    AND sp.viewcount <= GREATEST(COALESCE(tls.avg_question_views, 1) * 0.35, 1)
    AND (sp.comment_count >= 2 OR sp.answer_count >= 1)
  ORDER BY sp.composite_score DESC
  LIMIT 200
),
recent_activity_posts AS (
  SELECT
    sp.*,
    ( (sp.composite_score * 0.6) + (sp.comment_count * 1.5) + (COALESCE(sp.answer_count,0) * 2.0) + (CASE WHEN GREATEST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - sp.CreationDate))/86400.0, 0) < 14 THEN 15 ELSE 0 END) ) AS hot_score
  FROM scored_posts sp
  WHERE sp.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '14 days'
  ORDER BY hot_score DESC
  LIMIT 500
),
filtered_recent_activity AS (
  SELECT rap.question_id AS question_id, rap.Title AS title, rap.OwnerUserId AS owner_id, rap.composite_score AS composite_score, rap.viewcount AS viewcount, rap.age_days AS age_days
  FROM recent_activity_posts rap
  EXCEPT
  SELECT question_id, title, owner_id, composite_score, viewcount, age_days FROM top_per_tag_set
),
recent_activity_wrapped AS (
  SELECT
    qt.tag,
    fr.question_id,
    substring(regexp_replace(fr.title, '<[^>]+>', '', 'g'),1,160) ||
      CASE WHEN length(COALESCE(fr.title,'')) > 160 THEN '...' ELSE '' END AS title,
    fr.owner_id AS owner_id,
    fr.composite_score,
    fr.viewcount,
    fr.age_days,
    NULL::int AS rn,
    NULL::int AS rnk,
    NULL::numeric AS avg_question_views,
    NULL::int AS tag_question_count,
    NULL::numeric AS z_score_within_tag
  FROM filtered_recent_activity fr
  JOIN question_tags qt ON qt.question_id = fr.question_id
  LIMIT 1000
),
final_set AS (
  SELECT * FROM top_per_tag_set
  UNION
  SELECT * FROM unseen_gems
  UNION
  SELECT tag, question_id, title, owner_id, composite_score, viewcount, age_days, rn, rnk, avg_question_views, tag_question_count, z_score_within_tag FROM recent_activity_wrapped
),
deduped_final AS (
  SELECT DISTINCT ON (f.question_id)
    f.*,
    COALESCE(u.DisplayName, '') AS owner_displayname,
    u.Reputation AS owner_reputation,
    (SELECT a.Id FROM Posts a WHERE a.ParentId = f.question_id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC LIMIT 1) AS top_answer_id,
    (SELECT COALESCE(u2.Reputation,0) FROM Posts a JOIN Users u2 ON a.OwnerUserId = u2.Id WHERE a.ParentId = f.question_id ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS top_answerer_reputation,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.question_id AND pl.LinkTypeId = 3) AS duplicate_links_out_count,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.question_id) AS votes_total_fallback
  FROM final_set f
  LEFT JOIN Users u ON u.Id = f.owner_id
  ORDER BY f.question_id, COALESCE(f.rn, 9999), f.composite_score DESC
),
ranked_final AS (
  SELECT
    df.*,
    DENSE_RANK() OVER (ORDER BY df.composite_score DESC NULLS LAST) AS overall_rank,
    PERCENT_RANK() OVER (ORDER BY df.composite_score DESC NULLS LAST) AS overall_percent_rank,
    ROW_NUMBER() OVER () AS serial_no
  FROM deduped_final df
)
SELECT
  serial_no,
  tag,
  question_id,
  title,
  owner_id,
  owner_displayname,
  owner_reputation,
  composite_score,
  viewcount,
  age_days,
  rn,
  rnk,
  COALESCE(avg_question_views, 0) AS avg_question_views_for_tag,
  tag_question_count,
  z_score_within_tag,
  top_answer_id,
  top_answerer_reputation,
  duplicate_links_out_count,
  votes_total_fallback,
  overall_rank,
  overall_percent_rank
FROM ranked_final
ORDER BY overall_rank, tag, composite_score DESC
LIMIT 1000;