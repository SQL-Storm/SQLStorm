-- {"query": "4685.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1025} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestPostEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId,
      rpe.PostHistoryTypeId,
      rpe.CreationDate
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  UserContributions AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      SUM(p.ViewCount) AS TotalViews,
      SUM(p.Score) AS TotalScore
    FROM Posts AS p
    GROUP BY
      p.OwnerUserId
  ),
  RecentActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS RecentPosts,
      SUM(p.AnswerCount) AS RecentAnswers,
      SUM(p.CommentCount) AS RecentComments
    FROM Posts AS p
    WHERE
      p.CreationDate >= DATE('now', '-30 day')
    GROUP BY
      p.OwnerUserId
  )
SELECT
  u.DisplayName,
  u.Reputation,
  uc.PostsOwned,
  uc.QuestionsAsked,
  uc.AnswersGiven,
  ra.RecentPosts,
  ra.RecentAnswers,
  ra.RecentComments,
  COALESCE(lpe_body.UserId, lpe_title.UserId, lpe_tags.UserId) AS LastEditorUserId,
  COALESCE(lpe_body.CreationDate, lpe_title.CreationDate, lpe_tags.CreationDate) AS LastEditDate,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN INSTR(u.WebsiteUrl, 'stack') > 0 THEN 'StackExchange Site'
    ELSE 'External Site'
  END AS WebsiteType,
  CASE
    WHEN INSTR(u.AboutMe, 'SQL') > 0 OR INSTR(u.AboutMe, 'database') > 0 THEN 'SQL Enthusiast'
    ELSE 'General User'
  END AS UserInterest,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.UserId = u.Id AND v.VoteTypeId = 2 -- UpVote
  ) AS UpVotesGiven,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.UserId = u.Id AND v.VoteTypeId = 3 -- DownVote
  ) AS DownVotesGiven,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name LIKE '%Stack%' AND b.Class = 1 -- Gold badge
    ) THEN 'Achieved Stack Master'
    ELSE 'No Stack Master Badge'
  END AS BadgeStatus
FROM Users AS u
LEFT JOIN UserContributions AS uc
  ON u.Id = uc.OwnerUserId
LEFT JOIN RecentActivity AS ra
  ON u.Id = ra.OwnerUserId
LEFT JOIN LatestPostEdits AS lpe_body
  ON u.Id = lpe_body.UserId AND lpe_body.PostHistoryTypeId = 5 -- Edit Body
LEFT JOIN LatestPostEdits AS lpe_title
  ON u.Id = lpe_title.UserId AND lpe_title.PostHistoryTypeId = 4 -- Edit Title
LEFT JOIN LatestPostEdits AS lpe_tags
  ON u.Id = lpe_tags.UserId AND lpe_tags.PostHistoryTypeId = 6 -- Edit Tags
WHERE
  u.Reputation > 1000
  AND uc.PostsOwned > 5
  AND u.CreationDate < DATE('now', '-1 year')
ORDER BY
  u.Reputation DESC,
  uc.TotalScore DESC
LIMIT 100;
