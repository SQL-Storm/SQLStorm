-- {"query": "4349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1226} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  AvgPostScore AS (
    SELECT
      p.OwnerUserId,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AverageScore,
      MAX(p.Score) AS MaxScore
    FROM Posts AS p
    WHERE
      p.Score IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  RecentActivity AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.LastActivityDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) as rn
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount,
  COALESCE(aps.AverageScore, 0) AS AvgPostScore,
  COALESCE(aps.MaxScore, 0) AS MaxPostScore,
  CASE
    WHEN ra.LastActivityDate IS NULL THEN 'Never'
    WHEN ra.LastActivityDate < (CURRENT_TIMESTAMP - INTERVAL '30 days') THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackexchange.com%' THEN 'Stack Exchange Network Site'
    ELSE 'External Website'
  END AS WebsiteCategory,
  rpe_body.EditDate AS LastBodyEditDate,
  rpe_body.UserDisplayName AS LastBodyEditBy,
  rpe_title.EditDate AS LastTitleEditDate,
  rpe_title.UserDisplayName AS LastTitleEditBy,
  COUNT(c.Id) AS CommentCountOnOwnPosts,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
FROM Users AS u
LEFT JOIN UserPostCounts AS upc
  ON u.Id = upc.OwnerUserId
LEFT JOIN AvgPostScore AS aps
  ON u.Id = aps.OwnerUserId
LEFT JOIN RecentActivity AS ra
  ON u.Id = ra.OwnerUserId AND ra.rn = 1
LEFT JOIN RankedPostEdits AS rpe_body
  ON u.Id = rpe_body.UserId AND rpe_body.EditType = 'Edit Body' AND rpe_body.rn = 1
LEFT JOIN RankedPostEdits AS rpe_title
  ON u.Id = rpe_title.UserId AND rpe_title.EditType = 'Edit Title' AND rpe_title.rn = 1
LEFT JOIN Posts AS p_own
  ON u.Id = p_own.OwnerUserId
LEFT JOIN Comments AS c
  ON p_own.Id = c.PostId AND c.UserId <> u.Id -- Comments NOT made by the post owner
LEFT JOIN Votes AS v
  ON p_own.Id = v.PostId AND v.UserId <> u.Id -- Votes NOT cast by the post owner
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount,
  aps.AverageScore,
  aps.MaxScore,
  ra.LastActivityDate,
  WebsiteCategory,
  rpe_body.EditDate,
  rpe_body.UserDisplayName,
  rpe_title.EditDate,
  rpe_title.UserDisplayName
HAVING
  COUNT(c.Id) > 5 -- Only include users with at least 5 comments from others on their posts
  AND SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10 -- And at least 10 upvotes received
ORDER BY
  u.Reputation DESC,
  TotalPosts DESC
LIMIT 100;
