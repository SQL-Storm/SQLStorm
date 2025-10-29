-- {"query": "4247.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1166} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS total_posts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
      MAX(p.CreationDate) AS latest_post_date,
      AVG(p.Score) AS avg_post_score
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserEngagement AS (
    SELECT
      c.UserId,
      COUNT(DISTINCT c.Id) AS comment_count,
      SUM(c.Score) AS total_comment_score,
      MAX(c.CreationDate) AS latest_comment_date
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id
    FROM Users AS u
    WHERE
      u.Reputation > 10000
  )
SELECT
  u.DisplayName,
  u.Reputation,
  upa.total_posts,
  upa.question_count,
  upa.answer_count,
  upa.latest_post_date,
  upa.avg_post_score,
  ue.comment_count,
  ue.total_comment_score,
  ue.latest_comment_date,
  COALESCE(rpe.PostId, -1) AS latest_edited_post_id,
  COUNT(DISTINCT p_linked.Id) AS linked_posts_count,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count,
  SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS closed_posts_count,
  CASE
    WHEN EXISTS (SELECT 1 FROM Badges AS b WHERE b.UserId = u.Id AND b.Name LIKE '%Expert%') THEN 'Has Expert Badge'
    ELSE 'No Expert Badge'
  END AS expert_badge_status,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN LOWER(u.WebsiteUrl) LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related Site'
    ELSE 'External Website'
  END AS website_category,
  CASE
    WHEN DATE_PART('year', u.CreationDate) < 2010 THEN 'Pre-2010 User'
    WHEN DATE_PART('year', u.CreationDate) BETWEEN 2010 AND 2015 THEN '2010-2015 User'
    ELSE 'Post-2015 User'
  END AS user_creation_era
FROM Users AS u
LEFT OUTER JOIN UserPostActivity AS upa
  ON u.Id = upa.OwnerUserId
LEFT OUTER JOIN UserEngagement AS ue
  ON u.Id = ue.UserId
LEFT OUTER JOIN RankedPostEdits AS rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
LEFT OUTER JOIN Posts AS p
  ON u.Id = p.OwnerUserId
LEFT OUTER JOIN Votes AS v
  ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
LEFT OUTER JOIN PostLinks AS pl
  ON p.Id = pl.PostId
LEFT OUTER JOIN Posts AS p_linked
  ON pl.RelatedPostId = p_linked.Id
WHERE
  u.Id IN (SELECT Id FROM HighReputationUsers)
  OR u.Id IN (SELECT UserId FROM Badges WHERE Name = 'Editor')
GROUP BY
  u.DisplayName,
  u.Reputation,
  upa.total_posts,
  upa.question_count,
  upa.answer_count,
  upa.latest_post_date,
  upa.avg_post_score,
  ue.comment_count,
  ue.total_comment_score,
  ue.latest_comment_date,
  rpe.PostId,
  u.CreationDate,
  u.WebsiteUrl
HAVING
  COUNT(DISTINCT p.Id) > 50
ORDER BY
  u.Reputation DESC,
  upa.total_posts DESC,
  ue.comment_count DESC;
