-- {"query": "5964.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1160} 
WITH
  user_last_activity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      u.Location,
      u.WebsiteUrl,
      u.AboutMe,
      u.ProfileImageUrl,
      u.EmailHash,
      u.AccountId,
      ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
    FROM Users u
  ),
  recent_posts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.CreationDate,
      p.LastActivityDate,
      p.AcceptedAnswerId,
      p.ParentId,
      p.Body,
      p.LastEditorUserId,
      p.LastEditDate,
      p.ContentLicense,
      p.AnswerCount,
      p.CloseReasonTypesId,
      p.FavoriteCount,
      p.CommunityOwnedDate
    FROM Posts p
    WHERE p.LastActivityDate >= DATEADD(day, -7, GETDATE())
      OR p.CreationDate >= DATEADD(day, -7, GETDATE())
  ),
  post_history_expensive AS (
    SELECT
      ph.Id AS HistoryId,
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.RevisionGUID,
      ph.CreationDate AS HistoryDate,
      ph.UserId AS HistoryUserId,
      ph.UserDisplayName AS HistoryUserDisplayName,
      ph.Comment,
      ph.Text,
      ph.ContentLicense
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATEADD(day, -14, GETDATE())
  ),
  tag_aggregates AS (
    SELECT
      t.TagName,
      t.Count,
      t.IsModeratorOnly,
      t.IsRequired
    FROM Tags t
    WHERE t.Count > 100
  ),
  latest_votes AS (
    SELECT
      v.PostId,
      v.VoteTypeId,
      v.UserId,
      v.CreationDate,
      v.BountyAmount,
      ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    WHERE v.CreationDate >= DATEADD(day, -30, GETDATE())
  ),
  hot_scores AS (
    SELECT
      p.Id AS PostId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CreationDate,
      p.LastActivityDate,
      (p.Score * 2.0 + p.ViewCount * 0.5 + COALESCE(p.AnswerCount,0) * 3.0) AS HotMetric
    FROM Posts p
  )
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  u.LastAccessDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  u.ProfileImageUrl,
  u.EmailHash,
  u.AccountId,
  p.PostId,
  p.Title AS PostTitle,
  p.Tags,
  p.PostTypeId,
  p.Score AS PostScore,
  p.ViewCount AS PostViews,
  p.CommentCount AS PostComments,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate AS PostLastActivityDate,
  p.AcceptedAnswerId,
  p.ParentId,
  p.Body AS PostBody,
  p.LastEditorUserId,
  p.LastEditDate AS PostLastEditDate,
  p.ContentLicense AS PostContentLicense,
  p.AnswerCount,
  p.CloseReasonTypesId,
  p.FavoriteCount,
  p.CommunityOwnedDate,
  lh.HistoryId,
  lh.PostHistoryTypeId,
  lh.HistoryDate,
  lh.HistoryUserId,
  lh.HistoryUserDisplayName,
  lh.Comment AS HistoryComment,
  lh.Text AS HistoryText,
  tv.VoteTypeId,
  tv.UserId AS VoterUserId,
  tv.CreationDate AS VoteDate,
  tv.BountyAmount AS VoteBountyAmount,
  HS.HotMetric
FROM recent_posts p
LEFT JOIN latest_votes tv ON tv.PostId = p.PostId AND tv.rn = 1
LEFT JOIN hot_scores HS ON HS.PostId = p.PostId
LEFT JOIN post_history_expensive lh ON lh.PostId = p.PostId AND lh.HistoryDate = (
  SELECT MAX(HistoryDate) FROM post_history_expensive WHERE PostId = p.PostId
)
LEFT JOIN user_last_activity u ON u.UserId = p.OwnerUserId AND u.rn = 1
LEFT JOIN tag_aggregates ta ON ta.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
WHERE
  (p.PostTypeId = 1 OR p.PostTypeId = 2)
  AND (p.Score > 0 OR p.ViewCount > 100)
  AND (ta.IsModeratorOnly IS NULL OR ta.IsModeratorOnly = 0)
  AND (lh.PostHistoryTypeId IS NULL OR lh.PostHistoryTypeId IN (10,11,12,13,14))
ORDER BY HS.HotMetric DESC NULLS LAST, p.LastActivityDate DESC
LIMIT 500;