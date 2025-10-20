-- {"query": "37.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 895} 
WITH per_post AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner,
    COUNT(*) OVER () AS total_posts
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
recent_activity AS (
  SELECT
    th.PostId,
    th.PostHistoryTypeId,
    th.CreationDate AS HistoryDate,
    th.UserId AS HistoryUserId,
    th.Text,
    th.Comment
  FROM PostHistory th
  WHERE th.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
owner_agg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreation,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.WebsiteUrl,
    u.EmailHash,
    b.Count AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS Count
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
tag_explode AS (
  SELECT
    p.PostId,
    t.TagName,
    t.IsModeratorOnly,
    t.IsRequired
  FROM per_post p
  CROSS APPLY (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t
)
SELECT
  p.PostId,
  p.PostTypeId,
  p.Title,
  p.Tags,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.CommentCount,
  p.AnswerCount,
  p.FavoriteCount,
  p.Body,
  p.OwnerDisplayName,
  o.DisplayName AS OwnerDisplayNameAlias,
  o.Reputation,
  o.BadgeCount,
  p.LastEditorUserId,
  p.LastEditDate,
  p.ContentLicense,
  ra.HistoryDate AS Last30DayHistoryDate,
  ra.PostHistoryTypeId,
  ra.Text AS HistoryText,
  COUNT(DISTINCT cl.RelatedPostId) FILTER (WHERE cl.LinkTypeId = 1) AS LinkedPosts,
  COUNT(*) FILTER (WHERE vh.VoteTypeId = 2) AS UpModVotes,
  COUNT(*) FILTER (WHERE vh.VoteTypeId = 3) AS DownModVotes,
  MAX(vs.BountyAmount) FILTER (WHERE vs.BountyAmount IS NOT NULL) AS MaxBounty
FROM per_post p
LEFT JOIN Users o ON p.OwnerUserId = o.Id
LEFT JOIN recent_activity ra ON ra.PostId = p.PostId
LEFT JOIN (
  SELECT UserId, COUNT(*) AS Count
  FROM Badges
  GROUP BY UserId
) o ON o.UserId = p.OwnerUserId
LEFT JOIN PostLinks cl ON cl.PostId = p.PostId
LEFT JOIN Votes vh ON vh.PostId = p.PostId
LEFT JOIN Votes vs ON vs.PostId = p.PostId
GROUP BY
  p.PostId,
  p.PostTypeId,
  p.Title,
  p.Tags,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.CommentCount,
  p.AnswerCount,
  p.FavoriteCount,
  p.Body,
  p.OwnerDisplayName,
  o.DisplayName,
  o.Reputation,
  o.BadgeCount,
  p.LastEditorUserId,
  p.LastEditDate,
  p.ContentLicense,
  ra.HistoryDate,
  ra.PostHistoryTypeId,
  ra.Text
ORDER BY p.LastActivityDate DESC
LIMIT 100;