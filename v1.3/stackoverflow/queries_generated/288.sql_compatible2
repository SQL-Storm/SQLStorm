WITH
posts_by_user AS (
  SELECT
    COALESCE(p.OwnerUserId, -1) AS user_id,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS q_count,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS a_count,
    SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS q_views,
    SUM(COALESCE(p.Score,0)) AS total_post_score,
    SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = p.Id) THEN 1 ELSE 0 END) AS accepted_answers,
    MAX(p.LastActivityDate) AS last_post_activity,
    MIN(p.CreationDate) AS first_post_date,
    BOOL_OR(p.CommunityOwnedDate IS NOT NULL) AS any_community_owned
  FROM Posts p
  GROUP BY COALESCE(p.OwnerUserId, -1)
),
tag_exploded AS (
  SELECT p.Id AS post_id, COALESCE(p.OwnerUserId, -1) AS user_id,
         lower(trim(s.tg)) AS tag
  FROM Posts p
  JOIN LATERAL (
    -- use standard substring function and character_length replacement with LENGTH
    SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS tg
  ) s ON (p.PostTypeId = 1 AND p.Tags IS NOT NULL)
),
user_tag_stats AS (
  SELECT ut.user_id, ut.tag,
    COUNT(*) AS tag_count,
    SUM((SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ut.post_id AND p2.PostTypeId = 2)) AS answers_to_my_questions,
    ROW_NUMBER() OVER (PARTITION BY ut.user_id ORDER BY COUNT(*) DESC) AS tag_rank
  FROM tag_exploded ut
  GROUP BY ut.user_id, ut.tag
),
badge_agg AS (
  SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class=1) AS gold,
    COUNT(*) FILTER (WHERE b.Class=2) AS silver,
    COUNT(*) FILTER (WHERE b.Class=3) AS bronze,
    COUNT(*) AS total_badges,
    MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
history_counts AS (
  SELECT ph.UserId, 
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS edits,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS closes_reopens,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (17,35,36)) AS migrations,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 52) AS hot_questions
  FROM PostHistory ph
  GROUP BY ph.UserId
),
post_links_agg AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId,
    COUNT(*) OVER (PARTITION BY pl.PostId) AS out_links,
    COUNT(*) OVER (PARTITION BY pl.RelatedPostId) AS in_links
  FROM PostLinks pl
),
user_metrics AS (
  SELECT u.Id AS user_id,
    u.Reputation,
    u.CreationDate,
    u.DisplayName,
    u.Views AS profile_views,
    COALESCE(pb.q_count,0) AS questions,
    COALESCE(pb.a_count,0) AS answers,
    COALESCE(pb.total_post_score,0) AS post_score,
    COALESCE(bagg.gold,0) AS gold_badges,
    COALESCE(bagg.silver,0) AS silver_badges,
    COALESCE(bagg.bronze,0) AS bronze_badges,
    COALESCE(hc.edits,0) AS edits,
    COALESCE(hc.closes_reopens,0) AS closes_reopens,
    COALESCE(hc.migrations,0) AS migrations,
    CASE WHEN u.LastAccessDate IS NOT NULL THEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate))/86400 ELSE NULL END AS days_since_last_access,
    CASE WHEN COALESCE(pb.a_count,0) = 0 THEN NULL ELSE COALESCE(pb.accepted_answers * 1.0 / NULLIF(pb.a_count,0),0) END AS acceptance_ratio_estimate,
    (u.Reputation * 0.6 + COALESCE(bagg.gold,0) * 50 + COALESCE(bagg.silver,0) * 10 + COALESCE(bagg.bronze,0) * 2 + (COALESCE(pb.total_post_score,0) * 3) + GREATEST(0, 365 - COALESCE(EXTRACT(DAY FROM CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate), 365))/10) AS raw_health_score
  FROM Users u
  LEFT JOIN posts_by_user pb ON pb.user_id = u.Id
  LEFT JOIN badge_agg bagg ON bagg.UserId = u.Id
  LEFT JOIN history_counts hc ON hc.UserId = u.Id
),
top_tags_per_user AS (
  SELECT uts.user_id, uts.tag AS top_tag, uts.tag_count
  FROM user_tag_stats uts
  WHERE uts.tag_rank = 1
),
recent_activity_posts AS (
  SELECT p.OwnerUserId AS user_id, p.Id AS post_id, p.PostTypeId, p.Title,
    p.CreationDate, p.LastEditDate, p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COALESCE(p.LastEditDate,p.CreationDate) DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
user_recent_post AS (
  SELECT user_id, post_id, PostTypeId, Title, CreationDate, LastEditDate, Score
  FROM recent_activity_posts
  WHERE rn = 1
),
vote_type_counts AS (
  SELECT u.Id AS user_id,
    COALESCE(SUM(v2.count) FILTER (WHERE v2.VoteTypeId=1),0) AS accepted_votes,
    COALESCE(SUM(v2.count) FILTER (WHERE v2.VoteTypeId=2),0) AS upvotes,
    COALESCE(SUM(v2.count) FILTER (WHERE v2.VoteTypeId=3),0) AS downvotes,
    COALESCE(SUM(v2.count),0) AS total_votes
  FROM Users u
  LEFT JOIN (
    SELECT v.UserId, v.VoteTypeId, COUNT(*) AS count
    FROM Votes v
    GROUP BY v.UserId, v.VoteTypeId
    UNION ALL
    SELECT NULL AS UserId, NULL AS VoteTypeId, 0 AS count
  ) v2 ON v2.UserId = u.Id
  GROUP BY u.Id
),
ranked_users AS (
  SELECT um.user_id, um.Reputation, um.CreationDate, um.DisplayName, um.profile_views, um.questions, um.answers, um.post_score, um.gold_badges, um.silver_badges, um.bronze_badges, um.edits, um.closes_reopens, um.migrations, um.days_since_last_access, um.acceptance_ratio_estimate, um.raw_health_score,
    COALESCE(tt.top_tag, '<none>') AS top_tag,
    COALESCE(vtc.upvotes,0) AS upvotes,
    COALESCE(vtc.downvotes,0) AS downvotes,
    COALESCE(vtc.accepted_votes,0) AS accepted_votes,
    COALESCE(vtc.total_votes,0) AS total_votes,
    urp.post_id AS recent_post_id,
    urp.Title AS recent_post_title,
    urp.Score AS recent_post_score,
    RANK() OVER (ORDER BY um.raw_health_score DESC) AS health_rank,
    ROW_NUMBER() OVER (ORDER BY um.Reputation DESC, um.raw_health_score DESC) AS reputation_rank
  FROM user_metrics um
  LEFT JOIN top_tags_per_user tt ON tt.user_id = um.user_id
  LEFT JOIN vote_type_counts vtc ON vtc.user_id = um.user_id
  LEFT JOIN user_recent_post urp ON urp.user_id = um.user_id
)
SELECT
  r.user_id,
  r.DisplayName,
  r.Reputation,
  r.questions,
  r.answers,
  r.post_score,
  r.gold_badges, r.silver_badges, r.bronze_badges,
  r.edits, r.closes_reopens, r.migrations,
  r.top_tag,
  r.upvotes, r.downvotes, r.accepted_votes, r.total_votes,
  r.recent_post_id,
  COALESCE(r.recent_post_title, '(no recent post)') AS recent_post_title,
  r.recent_post_score,
  r.days_since_last_access,
  r.raw_health_score,
  r.health_rank,
  r.reputation_rank,
  CASE WHEN (r.questions + r.answers) > 0 AND (r.raw_health_score IS NOT NULL AND r.raw_health_score > 0) THEN
     (CASE WHEN POSITION('sql' IN lower(COALESCE(r.top_tag,''))) > 0 OR POSITION('postgres' IN lower(COALESCE(r.top_tag,''))) > 0 THEN 'likely-sql-contributor' ELSE 'community' END)
  ELSE 'lurker' END AS user_type_inference
FROM ranked_users r
WHERE (r.questions + r.answers) > 0
  AND COALESCE(r.Reputation,0) > 10
  AND NOT (r.DisplayName IS NULL OR trim(r.DisplayName) = '')
ORDER BY r.health_rank, r.reputation_rank
LIMIT 250;