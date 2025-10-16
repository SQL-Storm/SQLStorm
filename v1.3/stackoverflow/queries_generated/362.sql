-- {"query": "362.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18453} 
WITH
recent_posts AS (
    SELECT *
    FROM Posts
    WHERE CreationDate >= current_timestamp - interval '365 days'
),
user_posts AS (
    SELECT
        OwnerUserId,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS q_count,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS a_count,
        SUM(CASE WHEN PostTypeId IN (1,2) THEN 1 ELSE 0 END) AS total_posts,
        AVG(Score) FILTER (WHERE Score IS NOT NULL) AS avg_score,
        MAX(Score) FILTER (WHERE Score IS NOT NULL) AS max_score,
        COUNT(*) AS posts_in_year
    FROM recent_posts
    GROUP BY OwnerUserId
),
accepted_times AS (
    SELECT q.OwnerUserId AS OwnerUserId,
           AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS avg_seconds_to_accept,
           COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL) AS accepted_count
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
),
badge_summary AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze,
           COUNT(*) AS total_badges
    FROM Badges
    GROUP BY UserId
),
vote_pivot AS (
    SELECT p.OwnerUserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes_count,
           SUM(CASE WHEN v.VoteTypeId = 12 THEN 1 ELSE 0 END) AS spam_votes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
tag_counts AS (
    SELECT p.OwnerUserId,
           t.tag,
           COUNT(*) AS cnt
    FROM Posts p
    CROSS JOIN LATERAL (
       SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
),
top_tags AS (
    SELECT OwnerUserId, tag AS top_tag, cnt AS top_tag_count
    FROM (
       SELECT OwnerUserId, tag, cnt,
              ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY cnt DESC, tag) AS rn
       FROM tag_counts
    ) s
    WHERE rn = 1
),
comment_agg AS (
    SELECT UserId,
           COUNT(*) AS comments_made,
           AVG(length(Text)) AS avg_comment_len,
           COUNT(DISTINCT PostId) AS distinct_posts_commented
    FROM Comments
    GROUP BY UserId
),
history_agg AS (
    SELECT UserId,
           SUM(CASE WHEN PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS body_edits,
           SUM(CASE WHEN PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS title_edits,
           bool_or(PostHistoryTypeId = 12) AS has_deletion_event
    FROM PostHistory
    GROUP BY UserId
),
link_graph AS (
    SELECT ownerId,
           SUM(out_links) AS outgoing_links,
           SUM(in_links) AS incoming_links
    FROM (
       SELECT p.OwnerUserId AS ownerId, COUNT(pl.id) AS out_links, 0 AS in_links
       FROM Posts p
       LEFT JOIN PostLinks pl ON pl.PostId = p.Id
       GROUP BY p.OwnerUserId
       UNION ALL
       SELECT p.OwnerUserId AS ownerId, 0 AS out_links, COUNT(pl.id) AS in_links
       FROM Posts p
       LEFT JOIN PostLinks pl ON pl.RelatedPostId = p.Id
       GROUP BY p.OwnerUserId
    ) s
    GROUP BY ownerId
),
quarterly_post_counts AS (
    SELECT OwnerUserId,
           date_trunc('quarter', CreationDate) AS quarter,
           COUNT(*) AS posts_in_quarter
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId, date_trunc('quarter', CreationDate)
),
quarterly_growth AS (
    SELECT OwnerUserId, quarter, posts_in_quarter,
           LAG(posts_in_quarter) OVER (PARTITION BY OwnerUserId ORDER BY quarter) AS prev_posts,
           CASE WHEN LAG(posts_in_quarter) OVER (PARTITION BY OwnerUserId ORDER BY quarter) IS NULL THEN NULL
                ELSE (posts_in_quarter::float - LAG(posts_in_quarter) OVER (PARTITION BY OwnerUserId ORDER BY quarter)) / NULLIF(LAG(posts_in_quarter) OVER (PARTITION BY OwnerUserId ORDER BY quarter),0)
           END AS growth_ratio
    FROM quarterly_post_counts
),
latest_quarter_growth AS (
    SELECT OwnerUserId, growth_ratio
    FROM (
       SELECT OwnerUserId, growth_ratio, quarter,
              ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY quarter DESC) AS rn
       FROM quarterly_growth
    ) s
    WHERE rn = 1
),
post_score_median AS (
    SELECT OwnerUserId,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY Score) AS median_score
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
user_reputation_bucket AS (
    SELECT Id AS UserId,
           Reputation,
           CASE
             WHEN Reputation >= 100000 THEN 'Legend'
             WHEN Reputation >= 10000 THEN 'Expert'
             WHEN Reputation >= 1000 THEN 'Experienced'
             WHEN Reputation >= 100 THEN 'Active'
             ELSE 'New'
           END AS rep_bucket
    FROM Users
),
suspicious_users AS (
    SELECT p.OwnerUserId AS UserId
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 12
    GROUP BY p.OwnerUserId
    HAVING COUNT(*) > 5
),
suspicious_and_deleted AS (
    SELECT UserId FROM suspicious_users
    INTERSECT
    SELECT UserId FROM history_agg WHERE has_deletion_event
),
top_users AS (
    SELECT u.Id
    FROM Users u
    LEFT JOIN user_posts up ON up.OwnerUserId = u.Id
    LEFT JOIN badge_summary b ON b.UserId = u.Id
    WHERE (COALESCE(up.total_posts,0) >= 10 OR COALESCE(b.total_badges,0) >= 10)
    ORDER BY COALESCE(up.total_posts,0) DESC NULLS LAST, COALESCE(b.total_badges,0) DESC NULLS LAST
    LIMIT 250
),
main_rows AS (
    SELECT
      u.Id AS user_id,
      u.DisplayName AS display_name,
      u.Reputation AS reputation,
      urb.rep_bucket,
      COALESCE(up.q_count,0) AS q_count,
      COALESCE(up.a_count,0) AS a_count,
      COALESCE(up.total_posts,0) AS total_posts,
      ROUND(COALESCE(up.avg_score,0)::numeric,3) AS avg_score,
      COALESCE(pm.median_score,0) AS median_score,
      COALESCE(up.max_score,0) AS max_score,
      ROUND(COALESCE(at.avg_seconds_to_accept,0)::numeric,2) AS avg_seconds_to_accept,
      COALESCE(at.accepted_count,0) AS accepted_count,
      COALESCE(b.gold,0) AS gold,
      COALESCE(b.silver,0) AS silver,
      COALESCE(b.bronze,0) AS bronze,
      COALESCE(b.total_badges,0) AS total_badges,
      COALESCE(vp.upvotes_received,0) AS upvotes_received,
      COALESCE(vp.downvotes_received,0) AS downvotes_received,
      COALESCE(vp.spam_votes,0) AS spam_votes,
      tt.top_tag,
      COALESCE(tt.top_tag_count,0) AS top_tag_count,
      COALESCE(ca.comments_made,0) AS comments_made,
      ROUND(COALESCE(ca.avg_comment_len,0)::numeric,2) AS avg_comment_len,
      COALESCE(lg.outgoing_links,0) AS outgoing_links,
      COALESCE(lg.incoming_links,0) AS incoming_links,
      COALESCE(ha.body_edits,0) AS body_edits,
      COALESCE(ha.title_edits,0) AS title_edits,
      COALESCE(ha.has_deletion_event,false) AS has_deletion_event,
      EXISTS (SELECT 1 FROM suspicious_users su WHERE su.UserId = u.Id) AS is_suspicious,
      EXISTS (SELECT 1 FROM suspicious_and_deleted sd WHERE sd.UserId = u.Id) AS suspicious_and_deleted,
      lastp.last_post_title,
      lastp.last_post_date,
      lastc.last_comment_text,
      lastc.last_comment_date,
      (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id)) AS accepted_answers_given,
      COALESCE(latest.growth_ratio,0)::numeric AS latest_quarter_growth_ratio,
      ROUND(
        (
          COALESCE(up.total_posts,0) * 1.5
          + COALESCE(b.total_badges,0) * 4
          + COALESCE(vp.upvotes_received,0) * 0.8
          - COALESCE(vp.downvotes_received,0) * 1.2
          + COALESCE(at.accepted_count,0) * 2.5
          - COALESCE(vp.spam_votes,0) * 5
          + COALESCE(pm.median_score,0) * 0.5
        )::numeric,2) AS combined_score,
      RANK() OVER (ORDER BY
         (
          COALESCE(up.total_posts,0) * 1.5
          + COALESCE(b.total_badges,0) * 4
          + COALESCE(vp.upvotes_received,0) * 0.8
          - COALESCE(vp.downvotes_received,0) * 1.2
          + COALESCE(at.accepted_count,0) * 2.5
          - COALESCE(vp.spam_votes,0) * 5
          + COALESCE(pm.median_score,0) * 0.5
         ) DESC
      ) AS global_rank
    FROM top_users tu
    JOIN Users u ON u.Id = tu.Id
    LEFT JOIN user_posts up ON up.OwnerUserId = u.Id
    LEFT JOIN accepted_times at ON at.OwnerUserId = u.Id
    LEFT JOIN badge_summary b ON b.UserId = u.Id
    LEFT JOIN vote_pivot vp ON vp.OwnerUserId = u.Id
    LEFT JOIN post_score_median pm ON pm.OwnerUserId = u.Id
    LEFT JOIN top_tags tt ON tt.OwnerUserId = u.Id
    LEFT JOIN comment_agg ca ON ca.UserId = u.Id
    LEFT JOIN link_graph lg ON lg.ownerId = u.Id
    LEFT JOIN history_agg ha ON ha.UserId = u.Id
    LEFT JOIN user_reputation_bucket urb ON urb.UserId = u.Id
    LEFT JOIN latest_quarter_growth latest ON latest.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
       SELECT p.Title AS last_post_title, p.CreationDate AS last_post_date, p.Score AS last_post_score
       FROM Posts p
       WHERE p.OwnerUserId = u.Id
       ORDER BY p.CreationDate DESC
       LIMIT 1
    ) lastp ON true
    LEFT JOIN LATERAL (
       SELECT c.Text AS last_comment_text, c.CreationDate AS last_comment_date
       FROM Comments c
       WHERE c.UserId = u.Id
       ORDER BY c.CreationDate DESC
       LIMIT 1
    ) lastc ON true
)
SELECT * FROM main_rows
UNION ALL
SELECT
  NULL::int AS user_id,
  'AGGREGATE'::varchar AS display_name,
  SUM(reputation)::int AS reputation,
  'Mixed'::varchar AS rep_bucket,
  SUM(q_count)::int AS q_count,
  SUM(a_count)::int AS a_count,
  SUM(total_posts)::int AS total_posts,
  ROUND(AVG(NULLIF(avg_score,0)),3)::numeric AS avg_score,
  AVG(median_score)::numeric AS median_score,
  MAX(max_score)::int AS max_score,
  ROUND(AVG(NULLIF(avg_seconds_to_accept,0)),2)::numeric AS avg_seconds_to_accept,
  SUM(accepted_count)::int AS accepted_count,
  SUM(gold)::int AS gold,
  SUM(silver)::int AS silver,
  SUM(bronze)::int AS bronze,
  SUM(total_badges)::int AS total_badges,
  SUM(upvotes_received)::int AS upvotes_received,
  SUM(downvotes_received)::int AS downvotes_received,
  SUM(spam_votes)::int AS spam_votes,
  '---'::varchar AS top_tag,
  MAX(top_tag_count)::int AS top_tag_count,
  SUM(comments_made)::int AS comments_made,
  ROUND(AVG(NULLIF(avg_comment_len,0)),2)::numeric AS avg_comment_len,
  SUM(outgoing_links)::int AS outgoing_links,
  SUM(incoming_links)::int AS incoming_links,
  SUM(body_edits)::int AS body_edits,
  SUM(title_edits)::int AS title_edits,
  bool_or(has_deletion_event) AS has_deletion_event,
  bool_or(is_suspicious) AS is_suspicious,
  bool_or(suspicious_and_deleted) AS suspicious_and_deleted,
  NULL::varchar AS last_post_title,
  MAX(last_post_date) AS last_post_date,
  NULL::varchar AS last_comment_text,
  MAX(last_comment_date) AS last_comment_date,
  SUM(accepted_answers_given)::int AS accepted_answers_given,
  AVG(latest_quarter_growth_ratio)::numeric AS latest_quarter_growth_ratio,
  SUM(combined_score)::numeric AS combined_score,
  MIN(global_rank)::int AS global_rank
FROM main_rows
ORDER BY global_rank NULLS LAST;