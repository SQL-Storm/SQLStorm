-- {"query": "4670.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1266} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1 AND p.CreationDate >= DATE('now', '-1 year')
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(rp.PostId) AS TotalPosts,
      SUM(CASE WHEN rp.PostTypeName = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rp.PostTypeName = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(rp.Score) AS AvgPostScore,
      SUM(rp.FavoriteCount) AS TotalFavoriteCount,
      MAX(rp.PostCreationDate) AS LastPostCreationDate
    FROM Users AS u
    LEFT JOIN RankedPosts AS rp
      ON u.Id = rp.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  QuestionAnswers AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts AS q
    LEFT JOIN Posts AS a
      ON q.Id = a.ParentId
    WHERE
      q.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY
      q.Id,
      q.Title,
      q.CreationDate
  ),
  RecentPostActivity AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.LastActivityDate,
      ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM Posts AS p
    WHERE
      p.LastActivityDate >= DATE('now', '-7 days')
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation
    FROM Users
    WHERE
      Reputation > 100000
  )
SELECT
  ups.UserId,
  ups.DisplayName AS UserDisplayName,
  ups.Reputation,
  ups.UserCreationDate,
  ups.TotalPosts,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.AvgPostScore,
  ups.TotalFavoriteCount,
  ups.LastPostCreationDate,
  COALESCE(hr.DisplayName, 'Standard User') AS HighReputationIndicator,
  CASE
    WHEN ups.LastPostCreationDate IS NULL THEN 'No Recent Activity'
    WHEN ups.LastPostCreationDate < DATE('now', '-30 days') THEN 'Inactive'
    ELSE 'Active'
  END AS UserActivityStatus,
  rp.PostTypeName AS TopPostType,
  rp.Score AS TopPostScore,
  rp.ViewCount AS TopPostViewCount,
  qa.QuestionTitle,
  qa.QuestionCreationDate,
  qa.AnswerCount AS QuestionAnswerCount,
  qa.IsAcceptedAnswer,
  rpa.Title AS RecentActivityPostTitle,
  rpa.LastActivityDate AS RecentActivityTimestamp,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipStatus,
  LENGTH(p.Body) AS PostBodyLength,
  SUBSTRING(p.Body, 1, 100) AS PostBodyPreview,
  COALESCE(u.DisplayName, 'Deleted User') AS LastEditorDisplayName,
  p.LastEditDate,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Duplicates Linked'
  END AS DuplicateLinkStatus
FROM UserPostStats AS ups
LEFT JOIN HighReputationUsers AS hr
  ON ups.UserId = hr.Id
LEFT JOIN RankedPosts AS rp
  ON ups.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN Posts AS p
  ON p.Id = rp.PostId
LEFT JOIN QuestionAnswers AS qa
  ON qa.QuestionId = rp.PostId
LEFT JOIN RecentPostActivity AS rpa
  ON rpa.OwnerUserId = ups.UserId AND rpa.ActivityRank = 1
LEFT JOIN Users AS u
  ON p.LastEditorUserId = u.Id
WHERE
  ups.TotalPosts > 5
ORDER BY
  ups.Reputation DESC,
  ups.TotalPosts DESC;
