-- {"query": "21078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1814} 

WITH ActiveUsers AS (
  SELECT 
    u.Id AS user_id,
    u.Reputation,
    u.CreationDate AS user_creation,
    u.UpVotes + u.DownVotes AS total_votes,
    RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rep_rank
  FROM Users u
  WHERE u.Reputation > 1000
    AND u.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '365 days'
    AND u.Location IS NOT NULL
    AND LENGTH(u.Location) > 5
),
QuestionStats AS (
  SELECT 
    p.Id AS post_id,
    p.OwnerUserId,
    p.CreationDate AS post_creation,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(p.ClosedDate, p.CreationDate + INTERVAL '30 days') AS activity_end,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
      ELSE 'Open'
    END AS post_status,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS recent_question_rank,
    LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_question_score,
    AVG(p.Score) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.CreationDate 
                        ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS monthly_avg_score,
    CASE 
      WHEN p.Tags LIKE '%sql%' OR p.Tags LIKE '%database%' THEN 'Technical'
      WHEN p.Tags LIKE '%java%' OR p.Tags LIKE '%python%' THEN 'Programming'
      ELSE 'Other'
    END AS tag_category
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.Score >= -5
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
),
UserPerformance AS (
  SELECT 
    au.user_id,
    au.Reputation,
    au.rep_rank,
    COUNT(qs.post_id) AS question_count,
    AVG(qs.Score) AS avg_question_score,
    SUM(qs.ViewCount) AS total_views,
    SUM(COALESCE(qs.AnswerCount, 0)) AS total_answers,
    MAX(qs.post_creation) AS latest_post,
    MIN(qs.post_creation) AS earliest_post,
    COUNT(DISTINCT qs.tag_category) AS distinct_categories,
    -- Complex string manipulation for tag analysis
    STRING_AGG(
      SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2), 
      ', '
    ) AS primary_tags
  FROM ActiveUsers au
  LEFT JOIN QuestionStats qs ON au.user_id = qs.OwnerUserId
  LEFT JOIN Posts p ON qs.post_id = p.Id AND p.Tags IS NOT NULL
  WHERE qs.recent_question_rank <= 10  -- Only recent questions
    OR qs.post_id IS NULL  -- Include users with no recent questions
  GROUP BY au.user_id, au.Reputation, au.rep_rank
  HAVING COUNT(qs.post_id) > 0
    AND AVG(qs.Score) IS NOT NULL
),
VotePatterns AS (
  SELECT 
    v.PostId,
    v.UserId,
    vt.Name AS vote_type,
    COUNT(*) AS vote_frequency,
    AVG(v.CreationDate) AS avg_vote_time,
    -- Correlated subquery for vote density around this vote
    (SELECT COUNT(*) 
     FROM Votes v2 
     WHERE v2.UserId = v.UserId 
       AND v2.CreationDate BETWEEN v.CreationDate - INTERVAL '1 hour' AND v.CreationDate + INTERVAL '1 hour'
       AND v2.PostId != v.PostId) AS hourly_vote_density
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    AND v.UserId IS NOT NULL
    AND vt.Name IN ('UpMod', 'DownMod', 'Favorite')
  GROUP BY v.PostId, v.UserId, vt.Name, v.CreationDate
),
BadgeAchievers AS (
  SELECT 
    b.UserId,
    b.Name AS badge_name,
    b.Class,
    COUNT(*) AS badge_count,
    STRING_AGG(DISTINCT b.Name, ' | ') AS all_badges,
    -- Window function for badge progression
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS badge_sequence,
    LEAD(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS next_badge_date
  FROM Badges b
  WHERE b.Date > CURRENT_TIMESTAMP - INTERVAL '2 years'
    AND b.Class IN (1, 2)  -- Gold and Silver only
  GROUP BY b.UserId, b.Name, b.Class
  HAVING COUNT(*) > 1
)
SELECT 
  up.user_id,
  u.DisplayName,
  up.Reputation,
  up.rep_rank,
  up.question_count,
  ROUND(up.avg_question_score::numeric, 2) AS avg_score,
  up.total_views,
  up.total_answers,
  up.distinct_categories,
  up.primary_tags,
  -- Complex calculation for engagement score
  (up.total_views * 0.4 + up.total_answers * 10 + up.question_count * up.avg_question_score * 2) AS engagement_score,
  COALESCE(ba.all_badges, 'None') AS badges_earned,
  -- Handle NULL logic with COALESCE and CASE
  CASE 
    WHEN up.latest_post IS NULL THEN 'Inactive'
    WHEN up.latest_post > CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Very Active'
    WHEN up.latest_post > CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 'Active'
    ELSE 'Less Active'
  END AS activity_level,
  -- Subquery for total upvotes received
  (SELECT SUM(COALESCE(v.upvotes, 0)) 
   FROM (
     SELECT COUNT(*) AS upvotes
     FROM Votes v2
     WHERE v2.PostId IN (SELECT post_id FROM QuestionStats WHERE OwnerUserId = up.user_id)
       AND v2.VoteTypeId = 2  -- UpMod
     GROUP BY v2.PostId
   ) v
  ) AS total_upvotes_received,
  -- Correlated subquery for average comment length on user's posts
  AVG(
    LENGTH(c.Text)
  ) FILTER (WHERE c.UserId = up.user_id) AS avg_comment_length,
  -- Set operation to find users who voted on their own posts (should be rare)
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM VotePatterns vp 
      WHERE vp.UserId = up.user_id 
        AND vp.PostId IN (SELECT post_id FROM QuestionStats WHERE OwnerUserId = up.user_id)
    ) THEN 'Self-Voter'
    ELSE 'Clean'
  END AS voting_behavior,
  -- Window function for peer comparison
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY up.engagement_score) 
    OVER (PARTITION BY up.rep_rank / 100) AS median_engagement_by_rep_group
FROM UserPerformance up
JOIN Users u ON up.user_id = u.Id
LEFT JOIN BadgeAchievers ba ON up.user_id = ba.UserId
LEFT JOIN Comments c ON c.PostId IN (SELECT post_id FROM QuestionStats WHERE OwnerUserId = up.user_id)
LEFT JOIN VotePatterns vp ON vp.UserId = up.user_id
WHERE up.question_count >= 5
  AND (up.total_views > 1000 OR up.total_answers > 10)
  AND NOT EXISTS (
    -- Exclude users with negative voting patterns
    SELECT 1 FROM VotePatterns vp2 
    WHERE vp2.UserId = up.user_id 
      AND vp2.vote_type = 'DownMod' 
      AND vp2.vote_frequency > (
        SELECT AVG(vp3.vote_frequency) * 3 
        FROM VotePatterns vp3 
        WHERE vp3.vote_type = 'DownMod'
      )
  )
GROUP BY 
  up.user_id, u.DisplayName, up.Reputation, up.rep_rank, up.question_count, 
  up.avg_question_score, up.total_views, up.total_answers, up.distinct_categories,
  up.primary_tags, up.latest_post, ba.all_badges
HAVING COUNT(DISTINCT vp.vote_type) > 0 OR vp.vote_type IS NULL
ORDER BY engagement_score DESC, rep_rank ASC
LIMIT 100;
