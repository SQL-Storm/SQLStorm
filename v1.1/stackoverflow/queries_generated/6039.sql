-- {"query": "6039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 858} 
WITH
RecentActiveUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.LastAccessDate IS NOT NULL
),
TopTags AS (
  SELECT t.TagName, t.Count,
         ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
PostActivity AS (
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.OwnerUserId,
         p.CreationDate,
         p.ViewCount,
         p.Score,
         COALESCE(p.AnswerCount, 0) AS AnswerCount,
         p.Title,
         p.Tags,
         p.ParentId,
         p.AcceptedAnswerId,
         p.LastActivityDate,
         p.LastEditorUserId,
         p.LastEditDate,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesFromPost,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesFromPost
  FROM Posts p
  WHERE p.CreationDate >= TIMESTAMP '2022-01-01 00:00:00'
),
Dedupe AS (
  SELECT pa.*,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY pa.PostId) AS TotalUpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY pa.PostId) AS TotalDownVotes
  FROM PostActivity pa
  LEFT JOIN Votes v ON v.PostId = pa.PostId
  WHERE pa.PostTypeId IN (1,2)
)
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT r.PostId) AS PostsCreatedRecently,
  MAX(p.LastActivityDate) AS LastActivity,
  AVG(p.Score) AS AvgPostScore,
  SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
  SUM(COALESCE(p.AnswerCount,0)) AS TotalAnswers,
  STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TopTagNames,
  MAX(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS HasQuestions,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesTotal,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesTotal
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN PostActivity pa ON pa.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
LEFT JOIN (
  SELECT rp.Id AS PostId
  FROM Posts rp
  WHERE rp.ParentId IS NULL
) r ON r.PostId = p.Id
JOIN (
  SELECT DISTINCT rp.OwnerUserId, rp.Id AS PostId
  FROM Posts rp
  WHERE rp.CreationDate >= TIMESTAMP '2022-01-01 00:00:00'
) d ON d.PostId = p.Id
WHERE u.Id IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, u.DisplayName
LIMIT 100;