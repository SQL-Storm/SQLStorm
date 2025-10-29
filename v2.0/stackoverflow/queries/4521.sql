-- {"query": "4521.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1744}
WITH
  PostScores AS (
    SELECT
      p.Id AS PostId,
      p.Score,
      p.OwnerUserId,
      p.CreationDate,
      p.PostTypeId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.Score > 0
    GROUP BY
      p.Id,
      p.Score,
      p.OwnerUserId,
      p.CreationDate,
      p.PostTypeId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ps.PostId) AS PostsWithScore,
      SUM(ps.Score) AS TotalScoreFromPosts,
      AVG(ps.Score) AS AverageScorePerPost,
      SUM(ps.UpVotes) AS TotalUpVotesGiven,
      SUM(ps.DownVotes) AS TotalDownVotesGiven
    FROM Users u
    JOIN PostScores ps
      ON u.Id = ps.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  RecentPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId AS EditorUserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  PostWithRecentEditor AS (
    SELECT
      p.*,
      rpe.EditorUserId,
      rpe.EditDate
    FROM Posts p
    LEFT JOIN RecentPostEdits rpe
      ON p.Id = rpe.PostId AND rpe.rn = 1
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostsWithScore,
  ua.TotalScoreFromPosts,
  ua.AverageScorePerPost,
  ua.TotalUpVotesGiven,
  ua.TotalDownVotesGiven,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
  AVG(p.AnswerCount) AS AverageAnswersPerQuestion,
  COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS ClosedQuestionCount,
  MAX(p.FavoriteCount) AS MaxFavoriteCount,
  SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedCount,
  COUNT(DISTINCT CASE WHEN pwe.EditorUserId IS NOT NULL THEN pwe.Id ELSE NULL END) AS PostsWithEdits,
  AVG(EXTRACT(EPOCH FROM (pwe.LastActivityDate - pwe.EditDate)) / 86400.0) AS AvgDaysBetweenEditAndLastActivity,
  MAX(LENGTH(p.Body)) AS MaxPostBodyLength,
  MIN(p.Score) AS MinPostScore,
  CASE
    WHEN ua.Reputation > 100000 THEN 'High Reputation'
    WHEN ua.Reputation > 10000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationLevel,
  pwe.EditorUserId AS LatestEditorId,
  CASE WHEN pwe.EditorUserId IS NULL THEN 'No Edits' ELSE 'Has Edits' END AS EditStatus
FROM UserActivity ua
JOIN PostWithRecentEditor p
  ON ua.UserId = p.OwnerUserId
LEFT JOIN PostLinks pl
  ON p.Id = pl.PostId
LEFT JOIN PostLinks pl_dup
  ON p.Id = pl_dup.RelatedPostId AND pl_dup.LinkTypeId = 3
LEFT JOIN PostWithRecentEditor pwe
  ON p.Id = pwe.Id
WHERE
  p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostsWithScore,
  ua.TotalScoreFromPosts,
  ua.AverageScorePerPost,
  ua.TotalUpVotesGiven,
  ua.TotalDownVotesGiven,
  pwe.EditorUserId,
  pwe.EditDate,
  pwe.LastActivityDate,
  p.Body,
  p.AnswerCount,
  p.FavoriteCount,
  p.Score,
  p.CommunityOwnedDate,
  pwe.Id,
  CASE WHEN pwe.EditorUserId IS NULL THEN 'No Edits' ELSE 'Has Edits' END
HAVING
  COUNT(p.Id) > 50
UNION
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostsWithScore,
  ua.TotalScoreFromPosts,
  ua.AverageScorePerPost,
  ua.TotalUpVotesGiven,
  ua.TotalDownVotesGiven,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
  AVG(p.AnswerCount) AS AverageAnswersPerQuestion,
  COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS ClosedQuestionCount,
  MAX(p.FavoriteCount) AS MaxFavoriteCount,
  SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedCount,
  COUNT(DISTINCT CASE WHEN pwe.EditorUserId IS NOT NULL THEN pwe.Id ELSE NULL END) AS PostsWithEdits,
  AVG(EXTRACT(EPOCH FROM (pwe.LastActivityDate - pwe.EditDate)) / 86400.0) AS AvgDaysBetweenEditAndLastActivity,
  MAX(LENGTH(p.Body)) AS MaxPostBodyLength,
  MIN(p.Score) AS MinPostScore,
  CASE
    WHEN ua.Reputation > 100000 THEN 'High Reputation'
    WHEN ua.Reputation > 10000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationLevel,
  pwe.EditorUserId AS LatestEditorId,
  CASE WHEN pwe.EditorUserId IS NULL THEN 'No Edits' ELSE 'Has Edits' END AS EditStatus
FROM UserActivity ua
JOIN PostWithRecentEditor p
  ON ua.UserId = p.OwnerUserId
LEFT JOIN PostLinks pl
  ON p.Id = pl.PostId
LEFT JOIN PostLinks pl_dup
  ON p.Id = pl_dup.RelatedPostId AND pl_dup.LinkTypeId = 3
LEFT JOIN PostWithRecentEditor pwe
  ON p.Id = pwe.Id
WHERE
  p.CreationDate BETWEEN DATE '2022-01-01' AND DATE '2022-12-31'
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostsWithScore,
  ua.TotalScoreFromPosts,
  ua.AverageScorePerPost,
  ua.TotalUpVotesGiven,
  ua.TotalDownVotesGiven,
  pwe.EditorUserId,
  pwe.EditDate,
  pwe.LastActivityDate,
  p.Body,
  p.AnswerCount,
  p.FavoriteCount,
  p.Score,
  p.CommunityOwnedDate,
  pwe.Id,
  CASE WHEN pwe.EditorUserId IS NULL THEN 'No Edits' ELSE 'Has Edits' END
HAVING
  COUNT(p.Id) > 50;