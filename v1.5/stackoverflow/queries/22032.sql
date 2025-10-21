WITH user_stats AS (
  SELECT u.Id, u.DisplayName, u.CreationDate, u.Location,
         COUNT(p.Id) AS num_posts,
         SUM(p.Score) AS total_score,
         COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS num_questions,
         COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS num_answers,
         AVG(NULLIF(p.Score, 0)) AS avg_score
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Location
),
badge_stats AS (
  SELECT UserId,
         COUNT(*) AS num_badges,
         SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) AS badge_points
  FROM Badges
  GROUP BY UserId
),
vote_stats AS (
  SELECT UserId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_votes
  FROM Votes
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
comment_stats AS (
  SELECT UserId,
         COUNT(*) AS num_comments,
         AVG(NULLIF(Score, 0)) AS avg_comment_score
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
enriched_users AS (
  SELECT us.*,
         COALESCE(bs.num_badges, 0) AS num_badges,
         COALESCE(bs.badge_points, 0) AS badge_points,
         COALESCE(vs.net_votes, 0) AS net_votes,
         COALESCE(cs.num_comments, 0) AS num_comments,
         COALESCE(cs.avg_comment_score, 0) AS avg_comment_score,
         (SELECT tag FROM (
             SELECT unnest(string_to_array(NULLIF(substring(p.Tags FROM 2 FOR NULLIF(length(p.Tags) - 2, 0)), ''), '><')) AS tag,
                    COUNT(*) AS cnt
             FROM Posts p
             WHERE p.OwnerUserId = us.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
             GROUP BY tag
             ORDER BY cnt DESC
             LIMIT 1
         ) sub) AS top_tag
  FROM user_stats us
  LEFT JOIN badge_stats bs ON us.Id = bs.UserId
  LEFT JOIN vote_stats vs ON us.Id = vs.UserId
  LEFT JOIN comment_stats cs ON us.Id = cs.UserId
)
SELECT eu.*,
       CASE WHEN eu.Location IS NULL THEN 'Unknown' ELSE UPPER(SUBSTRING(eu.Location FROM 1 FOR 10)) END AS location_summary,
       (eu.total_score + eu.net_votes + eu.badge_points) / NULLIF(eu.num_posts + eu.num_comments, 0) AS overall_activity_score,
       ROW_NUMBER() OVER (ORDER BY (eu.total_score + eu.net_votes + eu.badge_points) / NULLIF(eu.num_posts + eu.num_comments, 0) DESC) AS rank_overall,
       ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM eu.CreationDate) ORDER BY eu.num_badges DESC) AS rank_by_year_badges
FROM enriched_users eu
WHERE eu.num_posts > 5 OR eu.num_comments > 10
ORDER BY overall_activity_score DESC NULLS LAST
FETCH FIRST 200 ROWS ONLY;