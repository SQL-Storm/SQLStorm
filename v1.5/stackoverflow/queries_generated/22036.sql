-- {"query": "22036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1038} 
WITH 
  user_reputation_stats AS (
    SELECT 
      u.Id, 
      u.Reputation, 
      COUNT(b.Id) AS badge_count, 
      COALESCE(SUM(CASE WHEN b.Class = 1 THEN 10 WHEN b.Class = 2 THEN 5 WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS badge_score
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100 AND u.AboutMe IS NOT NULL
    GROUP BY u.Id, u.Reputation
  ),
  post_vote_agg AS (
    SELECT 
      p.Id AS post_id, 
      p.OwnerUserId, 
      p.Score, 
      p.ViewCount, 
      p.PostTypeId,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS net_votes,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS post_rank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.PostTypeId
  ),
  tag_usage AS (
    SELECT 
      p.Id, 
      UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
      CASE WHEN p.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS is_sql_tagged
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ),
  linked_posts AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId, pl.LinkTypeId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
  )
SELECT 
  urs.Id, 
  urs.Reputation, 
  urs.badge_score,
  pva.post_id, 
  pva.net_votes,
  pva.post_rank,
  tu.tag,
  lp.RelatedPostId,
  CASE 
    WHEN urs.Reputation > 1000 THEN 'High Rep' 
    WHEN urs.Reputation BETWEEN 100 AND 1000 THEN 'Medium Rep' 
    ELSE 'Low Rep' 
  END AS rep_level,
  EXISTS (
    SELECT 1 
    FROM Comments c 
    WHERE c.PostId = pva.post_id AND c.Score > 5
  ) AS has_high_score_comments,
  RANK() OVER (ORDER BY urs.badge_score DESC, urs.Reputation DESC) AS overall_rank,
  CONCAT('User: ', COALESCE(u.DisplayName, 'Anonymous'), ' - Score: ', urs.badge_score::TEXT) AS summary_string,
  urs.badge_score + pva.net_votes AS combined_score,
  pva.net_votes * 1.0 / NULLIF(pva.ViewCount, 0) AS votes_per_view
FROM user_reputation_stats urs
INNER JOIN Users u ON urs.Id = u.Id
LEFT JOIN post_vote_agg pva ON urs.Id = pva.OwnerUserId AND pva.post_rank <= 3
LEFT JOIN tag_usage tu ON pva.post_id = tu.Id AND tu.is_sql_tagged = 1
LEFT JOIN linked_posts lp ON pva.post_id = lp.PostId
WHERE urs.Reputation IS NOT NULL 
  AND pva.net_votes > 0
  AND EXISTS (
    SELECT 1 
    FROM Posts sub_p 
    WHERE sub_p.OwnerUserId = urs.Id 
      AND sub_p.AcceptedAnswerId IS NOT NULL
      AND sub_p.Id IN (
        SELECT ph.PostId 
        FROM PostHistory ph 
        WHERE ph.PostHistoryTypeId = 24 
          AND ph.CreationDate > '2020-01-01'::timestamp
      )
  )
ORDER BY overall_rank, combined_score DESC
UNION ALL
SELECT 
  urs.Id, 
  urs.Reputation, 
  urs.badge_score,
  NULL AS post_id, 
  NULL AS net_votes,
  NULL AS post_rank,
  NULL AS tag,
  NULL AS RelatedPostId,
  CASE WHEN urs.Reputation < 100 THEN 'Inactive' ELSE 'Active' END AS rep_level,
  NULL AS has_high_score_comments,
  RANK() OVER (ORDER BY urs.badge_score DESC, urs.Reputation DESC) AS overall_rank,
  CONCAT('No Top Posts - User: ', COALESCE(u.DisplayName, 'Anonymous')) AS summary_string,
  urs.badge_score AS combined_score,
  NULL AS votes_per_view
FROM user_reputation_stats urs
INNER JOIN Users u ON urs.Id = u.Id
WHERE urs.Id NOT IN (
  SELECT DISTINCT OwnerUserId 
  FROM post_vote_agg 
  WHERE net_votes > 0
)
ORDER BY overall_rank DESC
LIMIT 1000;