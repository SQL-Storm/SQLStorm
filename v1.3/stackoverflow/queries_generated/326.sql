-- {"query": "326.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12633} 
WITH
base_posts AS (
  SELECT p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Body, p.OwnerUserId, p.OwnerDisplayName, p.LastEditorUserId,
         p.LastEditDate, p.LastActivityDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.ContentLicense,
         CASE WHEN p.PostTypeId = 1 THEN TRUE ELSE FALSE END AS IsQuestion,
         CASE WHEN p.PostTypeId = 2 THEN TRUE ELSE FALSE END AS IsAnswer,
         COALESCE(p.Tags, '') AS RawTags,
         CASE WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') ELSE ARRAY[]::varchar[] END AS TagArray
  FROM Posts p
),
question_tags AS (
  SELECT bp.Id AS PostId, bp.Title, bp.OwnerUserId, t.tag
  FROM base_posts bp
  CROSS JOIN LATERAL unnest(bp.TagArray) AS t(tag)
  WHERE bp.IsQuestion
),
tag_agg AS (
  SELECT qt.tag AS tag,
         count(*) AS questions,
         sum(COALESCE(p.ViewCount,0)) AS total_views,
         avg(COALESCE(p.Score,0)) AS avg_score,
         max(COALESCE(p.Score,0)) AS max_score
  FROM question_tags qt
  JOIN Posts p ON p.Id = qt.PostId
  GROUP BY qt.tag
),
user_posts AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
         sum(COALESCE(p.Score,0)) AS total_score,
         avg(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS avg_post_score,
         min(p.CreationDate) AS first_post,
         max(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_votes AS (
  SELECT v.PostId,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         sum(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
         sum(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS bounty_starts
  FROM Votes v
  GROUP BY v.PostId
),
comment_ranked AS (
  SELECT c.PostId, c.Id AS CommentId, c.Text,
         c.UserId, c.CreationDate,
         row_number() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC NULLS LAST, c.CreationDate DESC) AS rn,
         count(*) OVER (PARTITION BY c.PostId) AS comment_count
  FROM Comments c
),
post_comments AS (
  SELECT PostId,
         max(comment_count) AS comment_count,
         max(CASE WHEN rn = 1 THEN Text END) AS top_comment_text,
         max(CASE WHEN rn = 1 THEN UserId END) AS top_comment_user
  FROM comment_ranked
  GROUP BY PostId
),
post_link_stats AS (
  SELECT pl.PostId,
         sum(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS links_out,
         sum(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicates_out,
         count(*) AS total_links
  FROM PostLinks pl
  GROUP BY pl.PostId
),
post_history_agg AS (
  SELECT ph.PostId,
         sum(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS edits,
         sum(CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN 1 ELSE 0 END) AS closes_reopens,
         max(ph.CreationDate) AS last_history_change
  FROM PostHistory ph
  GROUP BY ph.PostId
),
badges_agg AS (
  SELECT b.UserId,
         count(*) AS badges_total,
         sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
         sum(CASE WHEN b.TagBased = B'1' THEN 1 ELSE 0 END) AS tag_based_badges
  FROM Badges b
  GROUP BY b.UserId
),
tag_top_posts AS (
  SELECT qt.tag, p.Id AS PostId, p.Title, p.Score, p.ViewCount,
         row_number() OVER (PARTITION BY qt.tag ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate DESC) AS tag_rank,
         dense_rank() OVER (PARTITION BY qt.tag ORDER BY p.Score DESC NULLS LAST) AS tag_score_rank
  FROM question_tags qt
  JOIN Posts p ON p.Id = qt.PostId
  WHERE p.PostTypeId = 1
),
high_rep AS (
  SELECT Id, DisplayName, Reputation FROM Users WHERE Reputation >= 10000
),
active_rep AS (
  SELECT DISTINCT u.Id, u.DisplayName, u.Reputation FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate > now() - interval '180 days'
),
elite_users AS (
  SELECT * FROM high_rep
  INTERSECT
  SELECT * FROM active_rep
),
high_rep_inactive AS (
  SELECT * FROM high_rep
  EXCEPT
  SELECT * FROM active_rep
),
post_scores AS (
  SELECT p.Id AS PostId, p.Title, p.OwnerUserId,
         p.Score,
         COALESCE(p.ViewCount,0) AS Views,
         COALESCE(v.upvotes,0) AS UpVotes,
         COALESCE(v.downvotes,0) AS DownVotes,
         COALESCE(c.comment_count,0) AS Comments,
         COALESCE(pls.links_out,0) AS LinksOut,
         COALESCE(pha.edits,0) AS Edits,
         CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END AS IsQuestion,
         CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END AS IsAnswer,
         (COALESCE(p.Score,0) * 2
          + ln(GREATEST(COALESCE(p.ViewCount,0),1)) * 1.5
          + COALESCE(v.upvotes,0) * 1.2
          - COALESCE(v.downvotes,0) * 2.5
          + COALESCE(c.comment_count,0) * 0.8
          + COALESCE(pha.edits,0) * 0.6
          + CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 5 ELSE 0 END
         )::numeric AS raw_engagement
  FROM Posts p
  LEFT JOIN post_votes v ON v.PostId = p.Id
  LEFT JOIN post_comments c ON c.PostId = p.Id
  LEFT JOIN post_link_stats pls ON pls.PostId = p.Id
  LEFT JOIN post_history_agg pha ON pha.PostId = p.Id
),
tag_post_scores AS (
  SELECT qt.tag, ps.PostId, ps.Title, ps.raw_engagement,
         ps.Views, ps.Score AS PostScore,
         avg(ps.raw_engagement) OVER (PARTITION BY qt.tag) AS avg_engagement_for_tag,
         percentile_disc(0.9) WITHIN GROUP (ORDER BY ps.raw_engagement) OVER (PARTITION BY qt.tag) AS p90_engagement_for_tag,
         row_number() OVER (PARTITION BY qt.tag ORDER BY ps.raw_engagement DESC) AS rn
  FROM question_tags qt
  JOIN post_scores ps ON ps.PostId = qt.PostId
),
tag_anomalies AS (
  SELECT DISTINCT t.tag,
         ta.avg_engagement_for_tag,
         ta.p90_engagement_for_tag,
         count(*) FILTER (WHERE ta.raw_engagement >= ta.p90_engagement_for_tag) OVER (PARTITION BY ta.tag) AS high_outliers,
         (SELECT count(*) FROM question_tags WHERE tag = t.tag) AS total_questions_with_tag
  FROM (SELECT DISTINCT tag FROM question_tags) t
  JOIN tag_post_scores ta ON ta.tag = t.tag
  WHERE ta.raw_engagement >= ta.p90_engagement_for_tag
),
user_aggregated AS (
  SELECT up.UserId,
         up.DisplayName,
         up.Reputation,
         COALESCE(b.badges_total,0) AS badges_total,
         COALESCE(b.gold_badges,0) AS gold_badges,
         COALESCE(b.silver_badges,0) AS silver_badges,
         COALESCE(b.bronze_badges,0) AS bronze_badges,
         COALESCE(up.questions_count,0) AS questions_count,
         COALESCE(up.answers_count,0) AS answers_count,
         COALESCE(up.total_score,0) AS total_score,
         CASE WHEN COALESCE(up.questions_count,0) = 0 THEN NULL ELSE (up.answers_count::numeric / up.questions_count) END AS answers_per_question,
         (SELECT psp.PostId FROM post_scores psp WHERE psp.OwnerUserId = up.UserId ORDER BY psp.raw_engagement DESC NULLS LAST LIMIT 1) AS top_post_id,
         (SELECT count(DISTINCT qt.tag) FROM question_tags qt WHERE qt.OwnerUserId = up.UserId) AS distinct_tags
  FROM user_posts up
  LEFT JOIN badges_agg b ON b.UserId = up.UserId
),
tag_user_matrix AS (
  -- a heavy, intentionally awkward full-outer union-style join for benchmarking
  SELECT t.tag,
         ua.UserId,
         ua.DisplayName,
         ta.questions AS tag_question_count,
         ua.questions_count AS user_questions,
         ua.answers_count AS user_answers,
         ua.distinct_tags,
         ta.avg_score AS tag_avg_score,
         COALESCE(ua.answers_count,0) + COALESCE(ta.questions,0) AS combined_activity,
         (CASE WHEN ua.top_post_id IS NOT NULL AND EXISTS (
             SELECT 1 FROM tag_post_scores tps WHERE tps.tag = t.tag AND tps.PostId = ua.top_post_id
           ) THEN TRUE ELSE FALSE END) AS user_top_in_tag
  FROM (SELECT DISTINCT tag FROM question_tags) t
  FULL OUTER JOIN tag_agg ta ON ta.tag = t.tag
  FULL OUTER JOIN user_aggregated ua ON 1 = 0
),
alerts AS (
  SELECT 'TAG_ANOMALY' AS event_type, tag::text AS key1, NULL::int AS key2, avg_engagement_for_tag::text AS detail
  FROM tag_anomalies
  UNION
  SELECT 'HIGH_REP_INACTIVE' AS event_type, NULL::text AS key1, Id AS key2, Reputation::text AS detail
  FROM high_rep_inactive
)
SELECT
  u.Id AS user_id,
  u.DisplayName,
  ua.questions_count,
  ua.answers_count,
  ua.total_score,
  ua.badges_total,
  ua.gold_badges,
  ua.silver_badges,
  ua.bronze_badges,
  ps.PostId,
  left(coalesce(ps.Title,''), 120) AS title_snippet,
  ps.raw_engagement,
  tps.tag AS primary_tag,
  row_number() OVER (PARTITION BY u.Id ORDER BY ps.raw_engagement DESC) AS user_post_rank,
  rank() OVER (ORDER BY ps.raw_engagement DESC) AS global_post_rank,
  CASE WHEN ta.p90_engagement_for_tag IS NOT NULL AND ps.raw_engagement >= ta.p90_engagement_for_tag THEN 'OUTLIER' ELSE 'NORMAL' END AS outlier_flag,
  COALESCE(tag_agg.total_views,0) AS tag_total_views,
  COALESCE(pls.total_links,0) AS post_total_links,
  COALESCE(pc.comment_count,0) AS post_comments,
  COALESCE(pha.edits,0) AS post_edits,
  COALESCE(length(coalesce(ps.Title,'')),0) AS title_length,
  left(coalesce(ps.Title,''), greatest(10, LEAST(length(coalesce(ps.Title,'')), 100))) || ' :: ' || coalesce(u.DisplayName,'[anon]') AS title_preview,
  COALESCE((SELECT uu.DisplayName FROM Users uu WHERE uu.Id = p.LastEditorUserId LIMIT 1), p.OwnerDisplayName, coalesce(u.DisplayName,'[unknown]')) AS last_editor_name,
  -- correlated boolean check: has this user a gold badge in this tag (approximation via tag name matching)
  (EXISTS (
     SELECT 1 FROM Badges b
     WHERE b.UserId = u.Id
       AND b.Class = 1
       AND (b.Name ILIKE ('%' || COALESCE(tps.tag,'') || '%') OR (b.TagBased = B'1' AND b.Name = tps.tag))
   )) AS user_has_gold_in_tag,
  -- combine with alerts via lateral correlated EXCEPT/INTERSECT demonstration
  (SELECT count(*) FROM alerts a WHERE a.event_type = 'TAG_ANOMALY' AND (a.key1 = tps.tag OR a.key1 IS NULL)) AS alert_count_for_tag
FROM post_scores ps
JOIN Posts p ON p.Id = ps.PostId
LEFT JOIN tag_post_scores tps ON tps.PostId = ps.PostId AND tps.rn = 1
LEFT JOIN tag_agg ON tag_agg.tag = tps.tag
LEFT JOIN post_link_stats pls ON pls.PostId = ps.PostId
LEFT JOIN post_comments pc ON pc.PostId = ps.PostId
LEFT JOIN post_history_agg pha ON pha.PostId = ps.PostId
LEFT JOIN user_aggregated ua ON ua.UserId = ps.OwnerUserId
LEFT JOIN Users u ON u.Id = ps.OwnerUserId
LEFT JOIN Tags tg ON tg.TagName = tps.tag
WHERE
  -- complicated predicate combining correlated subqueries, null logic, and arithmetic
  (
    ps.raw_engagement > (SELECT avg(raw_engagement) FROM post_scores) * 1.10
    OR ps.Score > 50
    OR u.Reputation > 10000
    OR EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Class = 1)
    OR (tps.tag IS NOT NULL AND EXISTS (SELECT 1 FROM tag_anomalies ta2 WHERE ta2.tag = tps.tag))
  )
  AND (u.Id IS NOT NULL OR ps.IsQuestion = 1)
ORDER BY global_post_rank ASC, ps.raw_engagement DESC
LIMIT 200;