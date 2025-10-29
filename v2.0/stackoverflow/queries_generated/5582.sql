-- {"query": "5582.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 753} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagAnalytics AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.ViewCount) AS MinViews,
    COUNT(*) AS PostsInTag
  FROM Tags tg
  CROSS APPLY (SELECT * FROM Posts p WHERE p.Id = tg.ExcerptPostId) AS p
  JOIN (SELECT value AS TagName FROM string_split(REPLACE(t.Tags, '<', ''), '>')) AS t
    ON t.TagName = tg.TagName
  GROUP BY t.TagName, t.Count
),
Hist AS (
  SELECT
    ht.Id AS HistoryId,
    ht.PostId,
    ht.PostHistoryTypeId,
    ht.CreationDate,
    ht.Text,
    ht.Comment,
    ht.UserId
  FROM PostHistory ht
  WHERE ht.PostHistoryTypeId IN (10, 16, 52, 53) -- close, community owned, hot Q moves
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
Combined AS (
  SELECT
    h.PostId,
    h.PostHistoryTypeId,
    h.CreationDate AS HistoryDate,
    u.UserId,
    u.DisplayName AS EditorName,
    u.Reputation,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  FROM Hist h
  LEFT JOIN Posts p ON p.Id = h.PostId
  LEFT JOIN UserActivity u ON u.UserId = h.UserId
  WHERE h.CreationDate > DATEADD(year, -1, GETDATE())
)
SELECT
  r.PostId,
  r.Title,
  r.Tags,
  r.Score,
  r.ViewCount,
  r.CreationDate,
  r.OwnerUserId,
  r.LastActivityDate,
  r.CommentCount,
  r.AnswerCount,
  a.TagName AS TopTag,
  a.AvgPostScore,
  a.MaxViews,
  a.MinViews,
  u.DisplayName AS LastEditor,
  u.Reputation AS EditorReputation,
  v.VoteCount
FROM RecentHot r
LEFT JOIN LATERAL (
  SELECT TOP 1 ta.TagName,
                ta.Count AS Count,
                ta.Count * 1.0 / NULLIF((SELECT SUM(Count) FROM Tags), 0) AS TagShare
  FROM TagAnalytics ta
  ORDER BY ta.Count DESC
) AS a ON 1=1
LEFT JOIN Votes v ON v.PostId = r.PostId
LEFT JOIN Users u ON u.Id = r.OwnerUserId
WHERE r.rn <= 100
ORDER BY r.ViewCount DESC, r.Score DESC, r.CreationDate DESC;