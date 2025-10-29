-- {"query": "4695.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1016} 

WITH
  _cte_post_scores AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Score,
      p.PostTypeId,
      p.ParentId,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RowNumScore,
      SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalScore,
      AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScore,
      COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId) AS PostCount,
      CASE
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
      END AS PostTypeString
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
  ),
  _cte_user_stats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(ps.Score) AS MaxPostScore,
      AVG(ps.Score) AS AvgPostScore,
      SUM(ps.Score) AS TotalPostScore,
      SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      CAST(AVG(ps.Score) AS INT) AS RoundedAvgScore
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN _cte_post_scores AS ps
      ON u.Id = ps.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  _cte_recent_activity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS RecentPostCount,
      MAX(p.LastActivityDate) AS LatestActivityDate
    FROM Posts AS p
    WHERE
      p.LastActivityDate >= DATE('now', '-30 day')
    GROUP BY
      p.OwnerUserId
  ),
  _cte_featured_posts AS (
    SELECT
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CommunityOwnedDate
    FROM Posts AS p
    WHERE
      p.CommunityOwnedDate IS NOT NULL
      AND p.PostTypeId IN (1, 2)
  )
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.UserCreationDate,
  us.BadgeCount,
  us.MaxPostScore,
  us.AvgPostScore,
  us.TotalPostScore,
  us.QuestionCount,
  us.AnswerCount,
  us.RoundedAvgScore,
  COALESCE(ra.RecentPostCount, 0) AS RecentPostCount,
  CASE
    WHEN us.Reputation > 100000 THEN 'Titan'
    WHEN us.Reputation > 50000 THEN 'Legend'
    WHEN us.Reputation > 10000 THEN 'Expert'
    WHEN us.Reputation > 1000 THEN 'Experienced'
    ELSE 'Novice'
  END AS ReputationTier,
  fp.Title AS FeaturedPostTitle,
  CASE
    WHEN fp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipStatus
FROM _cte_user_stats AS us
LEFT JOIN _cte_recent_activity AS ra
  ON us.UserId = ra.OwnerUserId
LEFT JOIN _cte_featured_posts AS fp
  ON us.UserId = fp.OwnerUserId AND fp.Id IN (
    SELECT
      Id
    FROM _cte_featured_posts
    ORDER BY
      CommunityOwnedDate DESC
    LIMIT 1
  )
WHERE
  us.TotalPostScore > 0
  AND us.AnswerCount > us.QuestionCount * 0.5
  AND us.DisplayName LIKE '%a%'
ORDER BY
  us.Reputation DESC,
  us.BadgeCount DESC
LIMIT 50;
