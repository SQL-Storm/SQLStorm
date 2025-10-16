WITH user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.Location, 'Unknown') AS Location,
    COUNT(DISTINCT p.Id) AS post_count,
    COUNT(DISTINCT c.Id) AS comment_count,
    COUNT(DISTINCT b.Id) AS badge_count,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS avg_question_score,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS avg_answer_score,
    COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS gold_badges,
    ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'XX'), 1, 2) ORDER BY u.Reputation DESC) AS location_rank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS global_rank
  FROM Users u
  LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT OUTER JOIN Comments c ON u.Id = c.UserId
  LEFT OUTER JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
    AND (u.Reputation > 1000 OR u.Views > 100)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.OwnerUserId,
    COALESCE(p.ViewCount, 0) * 1.0 / NULLIF(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)), 0) AS views_per_day,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS downvotes,
    (SELECT STRING_AGG(DISTINCT COALESCE(u2.DisplayName, 'Anonymous'), ', ') 
     FROM Comments c2 
     LEFT JOIN Users u2 ON c2.UserId = u2.Id 
     WHERE c2.PostId = p.Id
     -- LIMIT in scalar subquery is not standard; emulate by aggregation of distinct names
    ) AS top_commenters,
    CASE 
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
      WHEN p.AnswerCount > 0 THEN 'Has Answers'
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      ELSE 'Open Without Answers'
    END AS post_status,
    LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
    LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) AS moving_avg_score,
    p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= TIMESTAMP '2019-01-01 00:00:00'
    AND (p.Body IS NOT NULL AND LENGTH(p.Body) > 100)
),
tag_expertise AS (
  SELECT 
    tag_name,
    p.OwnerUserId,
    COUNT(*) AS tag_post_count,
    AVG(p.Score) AS avg_tag_score,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS resolved_questions
  FROM (
    SELECT 
      p.*,
      TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) AS raw_tags
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL 
      AND p.OwnerUserId IS NOT NULL
  ) p
  CROSS JOIN LATERAL (
    SELECT value AS tag_name
    FROM (
      WITH RECURSIVE split(s, rest) AS (
        SELECT
          CASE WHEN POSITION('><' IN p.raw_tags) = 0 THEN p.raw_tags ELSE SUBSTRING(p.raw_tags FROM 1 FOR POSITION('><' IN p.raw_tags)-1) END,
          CASE WHEN POSITION('><' IN p.raw_tags) = 0 THEN '' ELSE SUBSTRING(p.raw_tags FROM POSITION('><' IN p.raw_tags) + 2) END
        UNION ALL
        SELECT
          CASE WHEN POSITION('><' IN rest) = 0 THEN rest ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1) END,
          CASE WHEN POSITION('><' IN rest) = 0 THEN '' ELSE SUBSTRING(rest FROM POSITION('><' IN rest) + 2) END
        FROM split
        WHERE rest <> ''
      )
      SELECT s AS value FROM split
    ) s2
  ) tags
  GROUP BY tag_name, p.OwnerUserId
  HAVING COUNT(*) >= 3
)
SELECT 
  uam.DisplayName,
  uam.Location,
  uam.Reputation,
  uam.post_count,
  uam.comment_count,
  uam.badge_count,
  uam.gold_badges,
  uam.location_rank,
  uam.global_rank,
  ROUND(COALESCE(uam.avg_question_score, 0), 2) AS avg_question_score,
  ROUND(COALESCE(uam.avg_answer_score, 0), 2) AS avg_answer_score,
  pes.Title AS latest_post_title,
  pes.post_status,
  pes.views_per_day,
  pes.upvotes,
  pes.downvotes,
  pes.top_commenters,
  ROUND(COALESCE(pes.moving_avg_score, 0), 2) AS moving_avg_score,
  te.tag_name AS top_expertise_tag,
  te.tag_post_count,
  te.avg_tag_score,
  CASE 
    WHEN uam.Reputation > 50000 THEN 'Elite'
    WHEN uam.Reputation > 10000 THEN 'Expert'
    WHEN uam.Reputation > 3000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS user_tier,
  COALESCE(ph_count.edit_count, 0) AS total_edits,
  COALESCE(v_stats.favorite_count, 0) AS posts_favorited,
  EXTRACT(YEAR FROM (AGE(TIMESTAMP '2024-10-01 12:34:56', uam.CreationDate))) AS years_active
FROM user_activity_metrics uam
INNER JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId
LEFT JOIN LATERAL (
  SELECT tag_name, tag_post_count, avg_tag_score
  FROM tag_expertise te2
  WHERE te2.OwnerUserId = uam.Id
  ORDER BY tag_post_count DESC, avg_tag_score DESC
  LIMIT 1
) te ON true
LEFT JOIN (
  SELECT ph.UserId, COUNT(*) AS edit_count
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  GROUP BY ph.UserId
) ph_count ON uam.Id = ph_count.UserId
LEFT JOIN (
  SELECT v.UserId, COUNT(*) AS favorite_count
  FROM Votes v
  WHERE v.VoteTypeId = 5
  GROUP BY v.UserId
) v_stats ON uam.Id = v_stats.UserId
WHERE pes.ViewCount > 100
  AND (pes.upvotes - pes.downvotes) > -5
  AND (te.tag_name IS NULL OR te.avg_tag_score > 0)
  AND uam.location_rank <= 10
  AND NOT EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.OwnerUserId = uam.Id 
      AND p2.ClosedDate IS NOT NULL 
      AND p2.Score < -3
  )
ORDER BY 
  CASE WHEN uam.Reputation > 20000 THEN uam.Reputation * pes.views_per_day ELSE uam.Reputation END DESC,
  uam.badge_count DESC,
  pes.Score DESC
LIMIT 500;