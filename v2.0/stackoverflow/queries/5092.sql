-- {"query": "5092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1237}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopTagWiki AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    DATE_TRUNC('month', u.CreationDate) AS CreationMonth
  FROM Users u
),
PostActivity AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS HistoryUserId,
    ph.Comment AS HistoryComment,
    ph.Text AS HistoryText
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
    AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'
),
LinkCross AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    l.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes l ON pl.LinkTypeId = l.Id
  WHERE pl.LinkTypeId IN (1, 3)
),
CommentAnalysis AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId AS CommentUserId,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.CreationDate AS CommentDate
  FROM Comments c
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
VoteSummary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesSum,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesSum,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
    COUNT(*) AS VotesCount
  FROM Votes v
  GROUP BY v.PostId
),
Aggregated AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.Title,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.OwnerUserId,
    rap.ViewCount,
    rap.Score,
    rap.Tags,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.ContentLicense,
    SUM(COALESCE(vs.UpVotesSum,0)) AS TotalUpVotes,
    SUM(COALESCE(vs.DownVotesSum,0)) AS TotalDownVotes,
    SUM(COALESCE(vs.VotesCount,0)) AS TotalVotes,
    COUNT(DISTINCT lc.RelatedPostId) AS LinkedPostsCount,
    MAX(lc.LinkTypeName) AS MaxLinkType,
    MAX(ua.CreationMonth) AS CreatorCohort
  FROM RecentActivePosts rap
  LEFT JOIN VoteSummary vs ON vs.PostId = rap.PostId
  LEFT JOIN LinkCross lc ON lc.PostId = rap.PostId
  LEFT JOIN UserEngagement ua ON ua.UserId = rap.OwnerUserId
  GROUP BY
    rap.PostId, rap.PostTypeId, rap.Title, rap.CreationDate, rap.LastActivityDate,
    rap.OwnerUserId, rap.ViewCount, rap.Score, rap.Tags, rap.AnswerCount,
    rap.CommentCount, rap.FavoriteCount, rap.ContentLicense
)
SELECT
  a.PostId,
  p2.Name AS PostType,
  a.Title,
  a.CreationDate,
  a.LastActivityDate,
  a.OwnerUserId,
  a.ViewCount,
  a.Score,
  a.Tags,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  a.ContentLicense,
  a.TotalUpVotes,
  a.TotalDownVotes,
  a.TotalVotes,
  a.LinkedPostsCount,
  a.MaxLinkType,
  a.CreatorCohort,
  AVG(a.Score) OVER (
    PARTITION BY a.OwnerUserId
    ORDER BY a.CreationDate
    ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
  ) AS AvgScoreLast5,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = a.OwnerUserId AND c.CreationDate >= a.CreationDate - INTERVAL '365 days') AS OwnerPastYearComments,
  CASE WHEN a.TotalVotes > 50 OR a.AnswerCount > 5 THEN TRUE ELSE FALSE END AS HighEngagement,
  (SELECT STRING_AGG(t.TagName, ',') FROM Tags t WHERE t.IsModeratorOnly = FALSE AND t.TagName <> '' AND POSITION(t.TagName IN a.Tags) > 0) AS TagSummary
FROM Aggregated a
JOIN PostTypes p2 ON p2.Id = a.PostTypeId
ORDER BY a.TotalVotes DESC, a.LastActivityDate DESC
LIMIT 100;