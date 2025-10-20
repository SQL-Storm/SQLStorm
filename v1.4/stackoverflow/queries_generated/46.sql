-- {"query": "46.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 762} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.Body,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ClosedDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
PostHist AS (
  SELECT
    ph.Id AS HistId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.RevisionGUID,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text,
    ph.ContentLicense
  FROM PostHistory ph
  WHERE ph.CreationDate >= NOW() - INTERVAL '180 days'
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 0
),
Joined AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.LastAccessDate,
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeId,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViews,
    rp.CommentCount AS PostComments,
    rp.AnswerCount AS PostAnswers,
    ph.HistId,
    ph.PostHistoryTypeId,
    ph.UserId AS HistUserId,
    ph.Comment AS HistComment,
    ph.Text AS HistText,
    ph.CreationDate AS HistDate,
    ts.TagName
  FROM TopUsers tu
  LEFT JOIN RecentPosts rp ON rp.OwnerUserId = tu.UserId
  LEFT JOIN PostHist ph ON ph.PostId = rp.PostId
  LEFT JOIN TagStats ts ON ts.TagName = ANY(string_to_array(rp.Tags, '><'))
),
WindowAgg AS (
  SELECT
    UserId,
    DisplayName,
    Reputation,
    LastAccessDate,
    PostId,
    PostTitle,
    PostTypeId,
    PostScore,
    PostViews,
    PostComments,
    PostAnswers,
    HistId,
    PostHistoryTypeId,
    HistUserId,
    HistComment,
    HistDate,
    TagName,
    ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY HistDate DESC, PostScore DESC) AS rn
  FROM Joined
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  LastAccessDate,
  PostId,
  PostTitle,
  PostTypeId,
  PostScore,
  PostViews,
  PostComments,
  PostAnswers,
  HistId,
  PostHistoryTypeId,
  HistUserId,
  HistComment,
  HistDate,
  TagName
FROM WindowAgg
WHERE rn = 1
ORDER BY Reputation DESC NULLS LAST, LastAccessDate DESC
LIMIT 200;