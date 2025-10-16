-- {"query": "219.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3786} 
WITH
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '365 days'
),
exploded_tags AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         trim(t) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(
      string_to_array(
        substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,'')) - 2, 0)
      ), '><')
    ) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_stats AS (
  SELECT Tag,
         count(*) AS tag_count,
         avg(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_question_score,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_question_score,
         dense_rank() OVER (ORDER BY count(*) DESC) AS popularity_rank
  FROM exploded_tags et
  JOIN Posts p ON p.Id = et.PostId
  GROUP BY Tag
),
recent_contributors AS (
  SELECT DISTINCT OwnerUserId AS UserId FROM recent_posts WHERE OwnerUserId IS NOT NULL
  UNION
  SELECT DISTINCT UserId FROM Votes WHERE CreationDate >= now() - interval '365 days' AND UserId IS NOT NULL
),
user_activity AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) AS question_count,
         coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) AS answer_count,
         coalesce(count(p.Id),0) AS total_posts,
         coalesce(sum(p.Score),0) AS total_post_score,
         round(nullif(avg(p.Score),0)::numeric,2) FILTER (WHERE p.Score IS NOT NULL) AS avg_post_score,
         max(p.CreationDate) AS last_post_date,
         (CASE WHEN u.WebsiteUrl IS NULL THEN 0 ELSE 1 END) AS has_website,
         (CASE WHEN u.AboutMe IS NOT NULL AND length(u.AboutMe)>0 THEN 1 ELSE 0 END) AS has_about
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.AboutMe
),
user_tag_counts AS (
  SELECT u.Id AS user_id,
         count(et.Tag) AS tags_used,
         string_agg(et.Tag, ',' ORDER BY count(et.Tag) DESC NULLS LAST) FILTER (WHERE et.Tag IS NOT NULL) AS tags_list,
         (array_agg(et.Tag ORDER BY count(et.Tag) DESC NULLS LAST))[1] AS top_tag
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN exploded_tags et ON et.PostId = p.Id
  GROUP BY u.Id
),
badge_scores AS (
  SELECT b.UserId AS user_id,
         count(*) AS badge_count,
         sum(case when b.Class = 1 then 5 when b.Class = 2 then 2 else 1 end) AS badge_weighted_score,
         max(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
votes_received AS (
  SELECT p.OwnerUserId AS user_id,
         count(v.*) FILTER (WHERE v.VoteTypeId IN (2,3)) AS votes_on_posts,
         count(v.*) FILTER (WHERE v.VoteTypeId = 5) AS favorites_received,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) AS net_votes_received
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  GROUP BY p.OwnerUserId
),
links_summary AS (
  SELECT p.OwnerUserId AS user_id,
         count(pl.*) FILTER (WHERE pl.LinkTypeId = 1) AS outbound_links_count,
         count(pl.*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_mark_count
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  GROUP BY p.OwnerUserId
),
top_questions_with_median AS (
  SELECT q.Id AS question_id,
         q.OwnerUserId AS asker_id,
         q.Title,
         q.Score AS question_score,
         q.CreationDate,
         coalesce(
           (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2 AND a.Score IS NOT NULL), 0
         ) AS median_answer_score,
         coalesce(
           (SELECT count(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2), 0
         ) AS answer_count
  FROM Posts q
  WHERE q.PostTypeId = 1 AND q.CreationDate >= now() - interval '365 days'
  ORDER BY q.Score DESC
  LIMIT 100
),
active_intersect AS (
  SELECT rc.UserId
  FROM recent_contributors rc
  INTERSECT
  SELECT ua.user_id FROM user_activity ua WHERE ua.total_posts > 0
),
candidate_users AS (
  SELECT u.id
  FROM Users u
  WHERE u.Id IN (SELECT UserId FROM recent_contributors)
    OR u.Id IN (SELECT user_id FROM user_activity WHERE total_posts > 0)
    OR u.Id IN (SELECT UserId FROM Badges)
)
SELECT
  u.Id AS user_id,
  coalesce(u.DisplayName, '<anonymous>') || ' (id=' || u.Id || ')' AS display_label,
  ua.Reputation,
  ua.question_count,
  ua.answer_count,
  ua.total_posts,
  ua.total_post_score,
  coalesce(b.badge_count,0) AS badge_count,
  coalesce(b.badge_weighted_score,0) AS badge_score,
  coalesce(vr.votes_on_posts,0) AS votes_on_posts,
  coalesce(vr.net_votes_received,0) AS net_votes_received,
  coalesce(ls.outbound_links_count,0) AS outbound_links_count,
  utc.tags_used,
  utc.top_tag,
  CASE
    WHEN ua.last_post_date IS NULL THEN 'no_recent_posts'
    WHEN ua.last_post_date > now() - interval '30 days' THEN 'active_30d'
    WHEN ua.last_post_date > now() - interval '90 days' THEN 'active_90d'
    ELSE 'dormant'
  END AS recent_activity_bucket,
  -- composite performance metric (arbitrary weights)
  (coalesce(ua.total_post_score,0)
   + (coalesce(b.badge_weighted_score,0) * 4)
   + (coalesce(vr.net_votes_received,0) * 2)
   + (ua.question_count * 6)
   + (ua.answer_count * 3)
  ) AS composite_score,
  dense_rank() OVER (ORDER BY
    (coalesce(ua.total_post_score,0)
     + (coalesce(b.badge_weighted_score,0) * 4)
     + (coalesce(vr.net_votes_received,0) * 2)
     + (ua.question_count * 6)
     + (ua.answer_count * 3)
    ) DESC
  ) AS composite_rank,
  -- correlated scalar subquery: number of this user's questions whose highest answer has score greater than question score*0.5
  (SELECT count(*)
   FROM Posts q
   WHERE q.OwnerUserId = u.Id AND q.PostTypeId = 1
     AND EXISTS (
       SELECT 1 FROM Posts a
       WHERE a.ParentId = q.Id AND a.PostTypeId = 2
         AND a.Score > coalesce(q.Score,0) * 0.5
     )
  ) AS questions_with_strong_answers,
  -- lateral correlated: latest comment text on top-scoring post, with NULL logic and string truncation
  coalesce(lc.latest_comment_snippet, '<no_comments>') AS latest_comment_snippet,
  -- boolean-ish flags
  (CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END) AS has_website_flag,
  (CASE WHEN ua.Reputation >= 10000 THEN 'trusted' WHEN ua.Reputation >= 1000 THEN 'established' ELSE 'new' END) AS reputation_bucket,
  -- set-operator derived flag
  (CASE WHEN a.UserId IS NOT NULL THEN true ELSE false END) AS in_recent_contributors,
  -- string expression mixing tags and badges
  coalesce(utc.top_tag, '<none>') || '|' || coalesce(b.badge_count::text, '0') AS top_tag_and_badge_count
FROM candidate_users c
JOIN Users u ON u.Id = c.id
LEFT JOIN user_activity ua ON ua.user_id = u.Id
LEFT JOIN user_tag_counts utc ON utc.user_id = u.Id
LEFT JOIN badge_scores b ON b.user_id = u.Id
LEFT JOIN votes_received vr ON vr.user_id = u.Id
LEFT JOIN links_summary ls ON ls.user_id = u.Id
LEFT JOIN LATERAL (
  SELECT left(ca.Text, 120) || CASE WHEN length(ca.Text) > 120 THEN '...' ELSE '' END AS latest_comment_snippet
  FROM Comments ca
  WHERE ca.UserId = u.Id OR ca.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
  ORDER BY ca.CreationDate DESC
  LIMIT 1
) lc ON true
LEFT JOIN (SELECT UserId FROM recent_contributors LIMIT 1) a ON a.UserId = u.Id
WHERE u.Id IN (SELECT Id FROM Users) -- trivial filter to allow planner variation
ORDER BY composite_score DESC NULLS LAST
LIMIT 250;