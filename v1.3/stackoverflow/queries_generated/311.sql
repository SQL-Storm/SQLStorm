-- {"query": "311.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16939} 
WITH
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= current_timestamp - interval '180 days'
),
safe_tags AS (
  SELECT p.Id AS PostId,
         CASE
           WHEN p.Tags IS NULL OR length(p.Tags) < 3 THEN NULL
           ELSE string_to_array(substring(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), '><')
         END AS tag_array
  FROM Posts p
),
post_tags AS (
  SELECT p.PostId, t.tag
  FROM safe_tags p
  CROSS JOIN LATERAL unnest(p.tag_array) AS t(tag)
  WHERE p.tag_array IS NOT NULL
),
post_votes AS (
  SELECT v.PostId,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         sum(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
         sum(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted,
         sum(CASE WHEN v.VoteTypeId IN (8,9) THEN coalesce(v.BountyAmount,0) ELSE 0 END) AS bounty_total
  FROM Votes v
  GROUP BY v.PostId
),
post_history_stats AS (
  SELECT ph.PostId,
         count(*) AS revision_count,
         count(distinct ph.UserId) AS distinct_editors,
         max(ph.CreationDate) AS last_revision,
         min(ph.CreationDate) AS first_revision,
         sum(CASE WHEN ph.PostHistoryTypeId IN (10,12) THEN 1 ELSE 0 END) AS close_or_delete_count
  FROM PostHistory ph
  GROUP BY ph.PostId
),
question_top_answer AS (
  SELECT q.Id AS QuestionId,
         (SELECT a.Id FROM Posts a WHERE a.ParentId = q.Id ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS TopAnswerId,
         (SELECT a.Score FROM Posts a WHERE a.ParentId = q.Id ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS TopAnswerScore,
         (SELECT a.OwnerUserId FROM Posts a WHERE a.ParentId = q.Id ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS TopAnswerOwner
  FROM Posts q
  WHERE q.PostTypeId = 1
),
tag_stats AS (
  SELECT pt.tag AS TagName,
         sum(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
         sum(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
         sum(CASE WHEN p.PostTypeId = 1 THEN coalesce(p.ViewCount,0) ELSE 0 END) AS total_views,
         avg(CASE WHEN p.PostTypeId = 1 THEN CAST(p.Score AS numeric) ELSE NULL END) AS avg_question_score,
         avg(CASE WHEN p.PostTypeId = 2 THEN CAST(p.Score AS numeric) ELSE NULL END) AS avg_answer_score,
         sum(coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) AS net_votes,
         max(p.CreationDate) AS last_activity
  FROM post_tags pt
  LEFT JOIN Posts p ON p.Id = pt.PostId
  LEFT JOIN post_votes v ON v.PostId = p.Id
  GROUP BY pt.tag
),
tag_recent_activity AS (
  SELECT pt.tag AS TagName,
         count(*) AS recent_post_count,
         sum(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS recent_score
  FROM post_tags pt
  JOIN recent_posts p ON p.Id = pt.PostId
  GROUP BY pt.tag
),
user_post_tags AS (
  SELECT u.Id AS UserId, u.DisplayName, p.Id AS PostId, p.Score AS PostScore, pt.tag
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  JOIN post_tags pt ON pt.PostId = p.Id
),
user_tag_contribs AS (
  SELECT ut.UserId, ut.DisplayName, ut.tag,
         count(*) AS posts_by_user_in_tag,
         sum(coalesce(ut.PostScore,0)) AS score_by_user_in_tag,
         row_number() OVER (PARTITION BY ut.tag ORDER BY count(*) DESC, sum(coalesce(ut.PostScore,0)) DESC) AS contributor_rank
  FROM user_post_tags ut
  GROUP BY ut.UserId, ut.DisplayName, ut.tag
),
top_contributors_per_tag AS (
  SELECT tag, UserId, DisplayName, posts_by_user_in_tag, score_by_user_in_tag
  FROM user_tag_contribs
  WHERE contributor_rank <= 3
),
tag_top_contributors_agg AS (
  SELECT tag AS TagName,
         string_agg(concat(DisplayName, ' (', posts_by_user_in_tag, '/', score_by_user_in_tag, ')'), ', ') AS top_contributors
  FROM top_contributors_per_tag
  GROUP BY tag
),
tag_hotness AS (
  SELECT COALESCE(ts.TagName, tra.TagName) AS TagName,
         COALESCE(ts.question_count,0) AS question_count,
         COALESCE(ts.answer_count,0) AS answer_count,
         COALESCE(ts.total_views,0) AS total_views,
         ts.avg_question_score,
         ts.avg_answer_score,
         COALESCE(ts.net_votes,0) AS net_votes,
         ts.last_activity,
         COALESCE(tra.recent_post_count,0) AS recent_post_count,
         COALESCE(tra.recent_score,0) AS recent_score,
         (COALESCE(tra.recent_post_count,0) * 2.0 + COALESCE(tra.recent_score,0) * 0.5 + COALESCE(ts.total_views,0) / greatest(COALESCE(ts.question_count,0),1) * 0.01) AS hotness_score
  FROM tag_stats ts
  FULL OUTER JOIN tag_recent_activity tra ON tra.TagName = ts.TagName
),
ranked_tags AS (
  SELECT *, dense_rank() OVER (ORDER BY hotness_score DESC NULLS LAST) AS hot_rank,
           rank() OVER (ORDER BY question_count DESC NULLS LAST) AS activity_rank
  FROM tag_hotness
),
top_tags AS (
  SELECT * FROM ranked_tags WHERE hot_rank <= 50 OR activity_rank <= 50
),
hot_tag_set AS (SELECT TagName FROM ranked_tags WHERE hot_rank <= 40),
active_tag_set AS (SELECT TagName FROM ranked_tags WHERE activity_rank <= 40),
hybrid_tag_set AS (
  SELECT TagName FROM hot_tag_set
  UNION
  SELECT TagName FROM active_tag_set
),
exclusive_hot_only AS (
  SELECT TagName FROM hot_tag_set
  EXCEPT
  SELECT TagName FROM active_tag_set
),
merge_candidates AS (
  SELECT TagName, 'hybrid' AS reason FROM hybrid_tag_set
  UNION
  SELECT TagName, 'hot_only' AS reason FROM exclusive_hot_only
),
final_candidate_tags AS (
  SELECT TagName FROM top_tags
  UNION
  SELECT TagName FROM merge_candidates
),
post_complex_stats AS (
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.Title,
         substring(coalesce(p.Body,''), 1, 400) AS BodySnippet,
         p.OwnerUserId,
         u.DisplayName AS OwnerName,
         p.Score,
         p.ViewCount,
         coalesce(v.upvotes,0) AS upvotes,
         coalesce(v.downvotes,0) AS downvotes,
         coalesce(phs.revision_count,0) AS revision_count,
         coalesce(phs.distinct_editors,0) AS distinct_editors,
         qta.TopAnswerId,
         qta.TopAnswerScore,
         qta.TopAnswerOwner,
         (SELECT count(distinct c.UserId) FROM Comments c WHERE c.PostId = p.Id) AS commenting_user_count,
         extract(epoch from (current_timestamp - coalesce(p.CreationDate, current_timestamp))) / 86400.0 AS age_days,
         ((coalesce(v.upvotes,0)+1) / greatest((coalesce(v.downvotes,0)+1),1) * ln(greatest((coalesce(phs.revision_count,0) + 1),1)) * (1 + least(1, (extract(epoch from (current_timestamp - coalesce(p.LastActivityDate, p.CreationDate)))/(60*60*24*30))))) AS volatility_score
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN post_votes v ON v.PostId = p.Id
  LEFT JOIN post_history_stats phs ON phs.PostId = p.Id
  LEFT JOIN question_top_answer qta ON qta.QuestionId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
final_selection AS (
  SELECT
    tt.TagName,
    tt.hot_rank,
    tt.activity_rank,
    tt.question_count,
    tt.answer_count,
    tt.total_views,
    tt.avg_question_score,
    tt.avg_answer_score,
    tt.net_votes,
    tt.last_activity,
    tt.recent_post_count,
    tt.recent_score,
    tt.hotness_score,
    coalesce(tca.top_contributors, '') AS top_contributors,
    (SELECT p.Id FROM Posts p JOIN post_tags pt ON pt.PostId = p.Id WHERE pt.tag = tt.TagName AND p.PostTypeId = 1 ORDER BY p.Score DESC NULLS LAST LIMIT 1) AS top_question_id,
    (SELECT p.Title FROM Posts p JOIN post_tags pt ON pt.PostId = p.Id WHERE pt.tag = tt.TagName AND p.PostTypeId = 1 ORDER BY p.Score DESC NULLS LAST LIMIT 1) AS top_question_title,
    (SELECT p.Score FROM Posts p JOIN post_tags pt ON pt.PostId = p.Id WHERE pt.tag = tt.TagName AND p.PostTypeId = 1 ORDER BY p.Score DESC NULLS LAST LIMIT 1) AS top_question_score,
    (SELECT a.Id FROM Posts a JOIN post_tags pt ON pt.PostId = a.Id WHERE pt.tag = tt.TagName AND a.PostTypeId = 2 ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS top_answer_id,
    (SELECT a.Score FROM Posts a JOIN post_tags pt ON pt.PostId = a.Id WHERE pt.tag = tt.TagName AND a.PostTypeId = 2 ORDER BY a.Score DESC NULLS LAST LIMIT 1) AS top_answer_score,
    (SELECT substring(p.Body, 1, 200) FROM Posts p JOIN post_tags pt ON pt.PostId = p.Id WHERE pt.tag = tt.TagName AND p.PostTypeId = 1 ORDER BY p.Score DESC NULLS LAST LIMIT 1) AS top_question_snippet,
    CASE WHEN tt.question_count > 0 THEN round(CAST(tt.answer_count AS numeric) / CAST(tt.question_count AS numeric), 2) ELSE NULL END AS answers_per_question,
    CASE WHEN (SELECT coalesce(sum(v2.downvotes),0) FROM Posts p2 JOIN post_votes v2 ON v2.PostId = p2.Id JOIN post_tags pt2 ON pt2.PostId = p2.Id WHERE pt2.tag = tt.TagName AND p2.PostTypeId = 1) > (SELECT coalesce(sum(v2.upvotes),0) FROM Posts p2 JOIN post_votes v2 ON v2.PostId = p2.Id JOIN post_tags pt2 ON pt2.PostId = p2.Id WHERE pt2.tag = tt.TagName AND p2.PostTypeId = 1) THEN true ELSE false END AS is_controversial,
    coalesce(tca.top_contributors, '---') AS contributors_summary
  FROM top_tags tt
  LEFT JOIN tag_top_contributors_agg tca ON tca.TagName = tt.TagName
  WHERE tt.TagName IN (SELECT TagName FROM final_candidate_tags)
  ORDER BY tt.hotness_score DESC NULLS LAST, tt.question_count DESC
  LIMIT 100
)
SELECT * FROM final_selection;