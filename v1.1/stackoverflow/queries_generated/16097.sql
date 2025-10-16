-- {"query": "16097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 228830, "output_tokens": 213031} 

WITH RECURSIVE user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
    DATE_PART('day', u.LastAccessDate - u.CreationDate) AS days_active,
    CASE 
      WHEN u.Location IS NULL THEN 'Unknown'
      WHEN LENGTH(TRIM(u.Location)) = 0 THEN 'Unknown'
      ELSE UPPER(LEFT(TRIM(u.Location), 1)) || LOWER(SUBSTRING(TRIM(u.Location), 2))
    END AS normalized_location
  FROM Users u
  WHERE u.Reputation > 1000
    AND u.CreationDate >= '2020-01-01'
),
post_statistics AS (
  SELECT 
    p.OwnerUserId,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS avg_question_score,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_answer_score,
    SUM(COALESCE(p.ViewCount, 0)) AS total_views,
    MAX(p.Score) AS max_score,
    STRING_AGG(DISTINCT SUBSTRING(p.Title, 1, 20), '; ') FILTER (WHERE p.PostTypeId = 1) AS sample_titles,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
    ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.ViewCount, 0)) DESC) AS view_rank
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
    AND p.CreationDate >= '2019-01-01'
  GROUP BY p.OwnerUserId
  HAVING COUNT(*) >= 5
),
badge_hierarchy AS (
  SELECT 
    b.UserId,
    b.Name AS badge_name,
    b.Class AS badge_class,
    COUNT(*) OVER (PARTITION BY b.UserId, b.Class) AS class_badge_count,
    DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date) AS badge_acquisition_rank,
    LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS prev_badge_date,
    LEAD(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS next_badge_date
  FROM Badges b
  WHERE b.TagBased = 0
),
engagement_scores AS (
  SELECT 
    c.UserId,
    COUNT(*) AS comment_count,
    AVG(LENGTH(c.Text)) AS avg_comment_length,
    SUM(CASE WHEN c.Score > 0 THEN c.Score ELSE 0 END) AS positive_comment_score,
    MAX(c.CreationDate) AS last_comment_date,
    COUNT(DISTINCT c.PostId) AS distinct_posts_commented
  FROM Comments c
  WHERE c.UserId IS NOT NULL
    AND c.CreationDate >= '2019-01-01'
  GROUP BY c.UserId
),
vote_patterns AS (
  SELECT 
    v.UserId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_given,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes_given,
    COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites_given,
    SUM(COALESCE(v.BountyAmount, 0)) AS total_bounty_offered,
    COUNT(DISTINCT DATE(v.CreationDate)) AS active_voting_days
  FROM Votes v
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
)
SELECT DISTINCT
  uam.Id AS user_id,
  uam.DisplayName AS display_name,
  uam.normalized_location,
  uam.Reputation,
  uam.net_votes,
  ROUND(uam.days_active::numeric, 2) AS days_active,
  COALESCE(ps.question_count, 0) AS questions_asked,
  COALESCE(ps.answer_count, 0) AS answers_given,
  ROUND(COALESCE(ps.avg_question_score, 0)::numeric, 2) AS avg_q_score,
  ROUND(COALESCE(ps.avg_answer_score, 0)::numeric, 2) AS avg_a_score,
  COALESCE(ps.total_views, 0) AS total_post_views,
  ps.view_rank,
  COALESCE(es.comment_count, 0) AS comments_made,
  ROUND(COALESCE(es.avg_comment_length, 0)::numeric, 2) AS avg_comment_len,
  COALESCE(vp.upvotes_given, 0) AS upvotes_cast,
  COALESCE(vp.downvotes_given, 0) AS downvotes_cast,
  COALESCE(vp.total_bounty_offered, 0) AS bounties_offered,
  COUNT(DISTINCT bh.badge_name) FILTER (WHERE bh.badge_class = 1) AS gold_badges,
  COUNT(DISTINCT bh.badge_name) FILTER (WHERE bh.badge_class = 2) AS silver_badges,
  COUNT(DISTINCT bh.badge_name) FILTER (WHERE bh.badge_class = 3) AS bronze_badges,
  CASE 
    WHEN uam.days_active > 0 THEN 
      ROUND((COALESCE(ps.question_count, 0) + COALESCE(ps.answer_count, 0))::numeric / NULLIF(uam.days_active, 0), 4)
    ELSE 0
  END AS posts_per_day,
  CASE
    WHEN COALESCE(vp.upvotes_given, 0) + COALESCE(vp.downvotes_given, 0) > 0 THEN
      ROUND(COALESCE(vp.upvotes_given, 0)::numeric / NULLIF(COALESCE(vp.upvotes_given, 0) + COALESCE(vp.downvotes_given, 0), 0), 3)
    ELSE NULL
  END AS upvote_ratio,
  (SELECT COUNT(*) 
   FROM Posts p2 
   WHERE p2.OwnerUserId = uam.Id 
     AND p2.PostTypeId = 2 
     AND p2.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
  ) AS accepted_answers,
  (SELECT STRING_AGG(DISTINCT pt.Name, ', ')
   FROM Posts p3
   INNER JOIN PostTypes pt ON p3.PostTypeId = pt.Id
   WHERE p3.OwnerUserId = uam.Id
  ) AS post_types_used,
  EXISTS (
    SELECT 1 
    FROM PostHistory ph 
    WHERE ph.UserId = uam.Id 
      AND ph.PostHistoryTypeId IN (4, 5, 6)
    LIMIT 1
  ) AS has_edited_posts,
  COALESCE(
    (SELECT MAX(p.Score) 
     FROM Posts p 
     WHERE p.OwnerUserId = uam.Id AND p.PostTypeId = 1),
    0
  ) AS best_question_score,
  ROW_NUMBER() OVER (
    PARTITION BY uam.normalized_location 
    ORDER BY uam.Reputation DESC, COALESCE(ps.total_views, 0) DESC
  ) AS location_rank,
  NTILE(10) OVER (ORDER BY uam.Reputation) AS reputation_decile
FROM user_activity_metrics uam
LEFT OUTER JOIN post_statistics ps ON uam.Id = ps.OwnerUserId
LEFT OUTER JOIN engagement_scores es ON uam.Id = es.UserId
LEFT OUTER JOIN vote_patterns vp ON uam.Id = vp.UserId
LEFT OUTER JOIN badge_hierarchy bh ON uam.Id = bh.UserId
WHERE (ps.question_count >= 3 OR ps.answer_count >= 5 OR es.comment_count >= 10)
  AND (vp.upvotes_given IS NULL OR vp.upvotes_given > 0)
  AND uam.Reputation BETWEEN 1000 AND 1000000
GROUP BY 
  uam.Id, uam.DisplayName, uam.normalized_location, uam.Reputation, 
  uam.net_votes, uam.days_active, ps.question_count, ps.answer_count,
  ps.avg_question_score, ps.avg_answer_score, ps.total_views, ps.view_rank,
  es.comment_count, es.avg_comment_length, vp.upvotes_given, 
  vp.downvotes_given, vp.total_bounty_offered
HAVING COUNT(DISTINCT bh.badge_name) >= 1
ORDER BY uam.Reputation DESC, COALESCE(ps.total_views, 0) DESC
LIMIT 500;
