-- {"query": "399.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14842} 
WITH
parsed_tags AS (
  SELECT
    p.Id AS question_id,
    lower(trim(s.tg)) AS tag,
    p.OwnerUserId,
    p.CreationDate AS q_creation,
    p.Score AS q_score,
    p.ViewCount AS q_views,
    p.Title,
    p.AnswerCount
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags,2,char_length(p.Tags)-2),'><')) AS tg
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
answers AS (
  SELECT
    a.ParentId AS question_id,
    COUNT(*) AS ans_count,
    AVG(a.Score) AS avg_ans_score,
    MIN(a.CreationDate) AS first_answer_date,
    MAX(a.Score) AS max_ans_score,
    SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_count
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
votes_by_post AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN v.VoteTypeId IN (5,8,9) THEN 1 ELSE 0 END) AS special_votes,
    COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
comments_by_post AS (
  SELECT
    c.PostId,
    COUNT(*) AS comment_count,
    AVG(COALESCE(c.Score,0)) AS avg_comment_score,
    MAX(c.CreationDate) AS last_comment_date,
    COUNT(DISTINCT c.UserId) AS distinct_commenters
  FROM Comments c
  GROUP BY c.PostId
),
tag_metrics AS (
  SELECT
    pt.tag,
    COUNT(DISTINCT pt.question_id) AS questions,
    ROUND(AVG(pt.q_score)::numeric,2) AS avg_q_score,
    ROUND(AVG(COALESCE(a.ans_count,0))::numeric,2) AS avg_answers_per_question,
    SUM(COALESCE(v.upvotes,0)) AS total_upvotes,
    SUM(COALESCE(v.downvotes,0)) AS total_downvotes,
    ROUND(AVG(EXTRACT(EPOCH FROM (a.first_answer_date - pt.q_creation)))::numeric,2) AS avg_first_answer_secs,
    SUM(COALESCE(c.comment_count,0)) AS total_comments,
    MAX(pt.q_views) AS max_views,
    SUM(COALESCE(pt.AnswerCount,0)) AS known_answer_counts
  FROM parsed_tags pt
  LEFT JOIN answers a ON a.question_id = pt.question_id
  LEFT JOIN votes_by_post v ON v.PostId = pt.question_id
  LEFT JOIN comments_by_post c ON c.PostId = pt.question_id
  GROUP BY pt.tag
),
user_tag_posts AS (
  SELECT
    pt.tag,
    q.OwnerUserId AS user_id,
    1 AS is_question,
    q.Id AS post_id,
    q.Score,
    q.CreationDate
  FROM parsed_tags pt
  INNER JOIN Posts q ON q.Id = pt.question_id
  WHERE q.OwnerUserId IS NOT NULL
  UNION ALL
  SELECT
    pt.tag,
    a.OwnerUserId AS user_id,
    0 AS is_question,
    a.Id AS post_id,
    a.Score,
    a.CreationDate
  FROM parsed_tags pt
  INNER JOIN Posts a ON a.ParentId = pt.question_id
  WHERE a.OwnerUserId IS NOT NULL
),
user_tag_contribs AS (
  SELECT
    utp.tag,
    utp.user_id,
    SUM(CASE WHEN utp.is_question = 1 THEN 1 ELSE 0 END) AS questions_authored,
    SUM(CASE WHEN utp.is_question = 0 THEN 1 ELSE 0 END) AS answers_authored,
    SUM(CASE WHEN utp.is_question = 0 THEN COALESCE(utp.Score,0) ELSE 0 END) AS answers_score_sum,
    SUM(CASE WHEN utp.is_question = 1 THEN COALESCE(utp.Score,0) ELSE 0 END) AS questions_score_sum,
    COUNT(DISTINCT utp.post_id) AS total_posts_for_tag,
    MAX(utp.CreationDate) AS last_activity_in_tag
  FROM user_tag_posts utp
  GROUP BY utp.tag, utp.user_id
),
ranked_user_tag_contribs AS (
  SELECT
    utc.*,
    ROW_NUMBER() OVER (PARTITION BY utc.tag ORDER BY utc.answers_authored DESC, utc.questions_authored DESC, utc.answers_score_sum DESC) AS rank_in_tag,
    SUM(utc.answers_authored + utc.questions_authored) OVER (PARTITION BY utc.tag) AS total_contributions_in_tag
  FROM user_tag_contribs utc
),
badges_by_user AS (
  SELECT
    b.UserId AS user_id,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
    SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS tag_based
  FROM Badges b
  GROUP BY b.UserId
),
top_users_by_tag AS (
  SELECT
    r.tag,
    jsonb_agg(jsonb_build_object(
      'rank', r.rank_in_tag,
      'user_id', r.user_id,
      'display_name', COALESCE(u.DisplayName, 'Anonymous'),
      'questions', r.questions_authored,
      'answers', r.answers_authored,
      'score_sum', (r.answers_score_sum + r.questions_score_sum),
      'last_activity', r.last_activity_in_tag,
      'reputation', u.Reputation,
      'gold', COALESCE(b.gold,0),
      'silver', COALESCE(b.silver,0),
      'bronze', COALESCE(b.bronze,0)
    ) ORDER BY r.rank_in_tag) AS top_users_json,
    MAX(u.Reputation) AS max_rep_among_top5,
    AVG(u.Reputation) AS avg_rep_among_top5
  FROM ranked_user_tag_contribs r
  LEFT JOIN Users u ON u.Id = r.user_id
  LEFT JOIN badges_by_user b ON b.user_id = r.user_id
  WHERE r.rank_in_tag <= 5
  GROUP BY r.tag
),
tag_monthly_activity AS (
  SELECT
    pt.tag,
    date_trunc('month', p.CreationDate) AS month,
    COUNT(*) AS questions_in_month
  FROM parsed_tags pt
  JOIN Posts p ON p.Id = pt.question_id
  GROUP BY pt.tag, date_trunc('month', p.CreationDate)
),
tag_trend AS (
  SELECT
    t1.tag,
    SUM(t1.questions_in_month) AS total_months_activity,
    SUM(CASE WHEN t1.month >= (CURRENT_DATE - INTERVAL '3 months') THEN t1.questions_in_month ELSE 0 END) AS last_3_months,
    SUM(CASE WHEN t1.month >= (CURRENT_DATE - INTERVAL '12 months') AND t1.month < (CURRENT_DATE - INTERVAL '3 months') THEN t1.questions_in_month ELSE 0 END) AS prior_9_months,
    CASE WHEN SUM(CASE WHEN t1.month >= (CURRENT_DATE - INTERVAL '12 months') AND t1.month < (CURRENT_DATE - INTERVAL '3 months') THEN t1.questions_in_month ELSE 0 END) = 0 THEN NULL
         ELSE ROUND(
           (SUM(CASE WHEN t1.month >= (CURRENT_DATE - INTERVAL '3 months') THEN t1.questions_in_month ELSE 0 END)::numeric
            / NULLIF(SUM(CASE WHEN t1.month >= (CURRENT_DATE - INTERVAL '12 months') AND t1.month < (CURRENT_DATE - INTERVAL '3 months') THEN t1.questions_in_month ELSE 0 END),0)
           ), 3)
    END AS growth_ratio_last3_vs_prior9
  FROM tag_monthly_activity t1
  GROUP BY t1.tag
),
recent_history_comment_by_tag AS (
  SELECT
    pt.tag,
    (
      SELECT ph.Comment
      FROM PostHistory ph
      WHERE ph.PostId IN (SELECT question_id FROM parsed_tags pt2 WHERE pt2.tag = pt.tag)
        AND ph.Comment IS NOT NULL
      ORDER BY ph.CreationDate DESC
      LIMIT 1
    ) AS recent_comment
  FROM (SELECT DISTINCT tag FROM parsed_tags) pt
),
tag_summary AS (
  SELECT
    tm.tag,
    tm.questions,
    tm.avg_q_score,
    tm.avg_answers_per_question,
    tm.total_upvotes,
    tm.total_downvotes,
    tm.avg_first_answer_secs,
    tm.total_comments,
    tt.last_3_months,
    tt.prior_9_months,
    tt.growth_ratio_last3_vs_prior9,
    tu.top_users_json,
    COALESCE(tu.max_rep_among_top5,0) AS max_rep_among_top5,
    COALESCE(tu.avg_rep_among_top5,0) AS avg_rep_among_top5,
    rh.recent_comment,
    initcap(replace(tm.tag,'-',' ')) AS pretty_tag,
    substring(tm.tag from 1 for 30) AS tag_brief,
    CASE WHEN EXISTS (SELECT 1 FROM Tags t WHERE lower(t.TagName) = tm.tag AND t.WikiPostId IS NOT NULL) THEN true ELSE false END AS has_wiki,
    (
      SELECT COUNT(*) FROM PostLinks pl
      WHERE pl.LinkTypeId = 3
        AND pl.PostId IN (SELECT question_id FROM parsed_tags pt2 WHERE pt2.tag = tm.tag)
    ) AS duplicate_links_count,
    (
      SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p
      JOIN parsed_tags pt2 ON p.Id = pt2.question_id
      WHERE pt2.tag = tm.tag AND p.OwnerUserId IS NOT NULL
    ) AS distinct_owners
  FROM tag_metrics tm
  LEFT JOIN tag_trend tt ON tt.tag = tm.tag
  LEFT JOIN top_users_by_tag tu ON tu.tag = tm.tag
  LEFT JOIN recent_history_comment_by_tag rh ON rh.tag = tm.tag
),
final_tag_with_ranks AS (
  SELECT
    ts.*,
    RANK() OVER (ORDER BY ts.questions DESC) AS rank_by_questions,
    ROUND((ts.questions::numeric / NULLIF(SUM(ts.questions) OVER (),0))::numeric,6) AS pct_of_total_questions,
    RANK() OVER (ORDER BY ts.total_upvotes DESC NULLS LAST) AS rank_by_upvotes,
    md5(concat(ts.tag,'|',ts.questions::text,'|',COALESCE(ts.total_upvotes,0)::text)) AS tag_signature,
    CASE WHEN ts.top_users_json IS NOT NULL THEN (ts.top_users_json->0->>'user_id')::int ELSE NULL END AS top_user0_id
  FROM tag_summary ts
)
(
  SELECT
    'TOP' AS bucket,
    f.tag,
    f.pretty_tag,
    f.tag_brief,
    f.questions,
    f.avg_q_score,
    f.avg_answers_per_question,
    f.avg_first_answer_secs,
    f.total_upvotes,
    f.total_downvotes,
    f.total_comments,
    f.last_3_months,
    f.prior_9_months,
    f.growth_ratio_last3_vs_prior9,
    f.distinct_owners,
    f.duplicate_links_count,
    f.has_wiki,
    f.recent_comment,
    f.top_users_json,
    f.max_rep_among_top5,
    f.avg_rep_among_top5,
    f.rank_by_questions,
    f.pct_of_total_questions,
    f.tag_signature,
    f.top_user0_id
  FROM final_tag_with_ranks f
  ORDER BY f.questions DESC, f.total_upvotes DESC NULLS LAST
  LIMIT 10
)
UNION ALL
(
  SELECT
    'BOTTOM' AS bucket,
    f.tag,
    f.pretty_tag,
    f.tag_brief,
    f.questions,
    f.avg_q_score,
    f.avg_answers_per_question,
    f.avg_first_answer_secs,
    f.total_upvotes,
    f.total_downvotes,
    f.total_comments,
    f.last_3_months,
    f.prior_9_months,
    f.growth_ratio_last3_vs_prior9,
    f.distinct_owners,
    f.duplicate_links_count,
    f.has_wiki,
    f.recent_comment,
    f.top_users_json,
    f.max_rep_among_top5,
    f.avg_rep_among_top5,
    f.rank_by_questions,
    f.pct_of_total_questions,
    f.tag_signature,
    f.top_user0_id
  FROM final_tag_with_ranks f
  WHERE f.questions > 0
  ORDER BY f.questions ASC, f.total_upvotes ASC NULLS LAST
  LIMIT 10
)
ORDER BY bucket, questions DESC;