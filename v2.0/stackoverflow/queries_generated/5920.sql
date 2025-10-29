-- {"query": "5920.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1229} 
WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
TagsPopularity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.CommentCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.Language,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC, p.LastActivityDate DESC) AS rn
  FROM Tags t
  JOIN Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE t.Count > 0
),
ActiveQuestions AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    q.AnswerCount,
    q.CommentCount
  FROM Posts q
  WHERE q.PostTypeId = 1 -- Questions
    AND q.ClosedDate IS NULL
),
CrossReference AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.AnswerCount,
    q.CommentCount,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.UserId AS VoterId
  FROM ActiveQuestions q
  LEFT JOIN Votes v
    ON v.PostId = q.QuestionId
     AND v.VoteTypeId IN (2, 3) -- Up/Down votes
),
JoinedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.ContentLicense,
    p.LastEditorUserId,
    p.LastEditDate,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.CreationDate AS PCreationDate
  FROM Posts p
),
WindowedStats AS (
  SELECT
    jp.PostId,
    jp.PostTypeId,
    jp.Title,
    jp.CreationDate,
    jp.LastActivityDate,
    jp.OwnerUserId,
    jp.Tags,
    jp.ViewCount,
    jp.Score,
    jp.AnswerCount,
    jp.CommentCount,
    jp.Authorized AS IsAuthorized
  FROM JoinedPosts jp
),
CorrelatedSummary AS (
  SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.OwnerUserId,
    rq.AnswerCount,
    rq.CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.QuestionId AND v.VoteTypeId = 2) AS UpVotesForQuestion,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.QuestionId AND v.VoteTypeId = 3) AS DownVotesForQuestion,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rq.QuestionId AND v.VoteTypeId = 8) AS AvgBounty
  FROM CrossReference rq
  GROUP BY rq.QuestionId, rq.Title, rq.CreationDate, rq.ViewCount, rq.Score, rq.OwnerUserId, rq.AnswerCount, rq.CommentCount
)
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.ProfileImageUrl,
  u.EmailHash,
  u.AccountId,
  p.PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  p.OwnerUserId,
  p.Tags,
  p.ViewCount,
  p.Score,
  p.AnswerCount,
  p.CommentCount,
  p.AcceptedAnswerId,
  p.ParentId,
  p.Body,
  p.ContentLicense,
  p.LastEditorUserId,
  p.LastEditDate,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  qs.QuestionId,
  qs.Version AS VersionOfQuestion,
  qs.Title AS QuestionTitle,
  qs.CreationDate AS QuestionCreationDate,
  qs.ViewCount AS QuestionViewCount,
  qs.Score AS QuestionScore,
  qs.OwnerUserId AS QuestionOwnerUserId,
  qs.AnswerCount AS QuestionAnswerCount,
  qs.CommentCount AS QuestionCommentCount,
  up.UpVotesForQuestion,
  up.DownVotesForQuestion,
  up.AvgBounty
FROM WindowedStats p
JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN CorrelatedSummary qs ON qs.QuestionId = p.PostId
ORDER BY u.Reputation DESC, p.ViewCount DESC
LIMIT 100;