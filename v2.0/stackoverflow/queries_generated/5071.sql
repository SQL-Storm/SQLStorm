-- {"query": "5071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1074} 
WITH RECURSIVE
-- CTE to generate a date-range series for performance measurement
DateSeries AS (
  SELECT date_trunc('day', CreationDate) AS day
  FROM Posts
  WHERE CreationDate IS NOT NULL
  GROUP BY date_trunc('day', CreationDate)
  UNION ALL
  SELECT day + INTERVAL '1 day'
  FROM DateSeries
  WHERE day + INTERVAL '1 day' < (SELECT MAX(CreationDate) FROM Posts)
),
PostStats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    COALESCE(vs.UpModCount, 0) AS UpModCount,
    COALESCE(vs.DownModCount, 0) AS DownModCount,
    COALESCE(vs.CloseVotes, 0) AS CloseVotes,
    COALESCE(vs.ReopenVotes, 0) AS ReopenVotes
  FROM Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
      SUM(CASE WHEN VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
      SUM(CASE WHEN VoteTypeId = 7 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = p.Id
  WHERE p.CreationDate IS NOT NULL
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS BadgesCount,
    SUM(COALESCE(b.Class, 0)) AS BadgeValue
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  CROSS APPLY string_to_array(p.Tags, '') -- placeholder; SQL dialect specific
  WHERE p.Tags IS NOT NULL
  GROUP BY t.TagName
),
-- Complex correlated subquery: for each post, find latest body edit by same user
LatestUserEdit AS (
  SELECT
    ph.PostId,
    ph.Text,
    ph.CreationDate,
    ph.UserId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (5, 8, 16) -- Edit Body / Community Owned / Post Migrated
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) = 1
)
SELECT
  ps.Id AS PostId,
  ps.PostTypeId,
  pt.Name AS PostTypeName,
  ps.Title,
  ps.Tags,
  ps.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  ps.Score,
  ps.ViewCount,
  ps.CommentCount,
  ps.LastActivityDate,
  pc.Name AS CloseReason,
  pcId.Name AS ClosedByReason,
  NULLIF(ts.UpModCount, 0) AS UpModVotes,
  NULLIF(ts.DownModCount, 0) AS DownModVotes,
  NULLIF(ts.CloseVotes, 0) AS CloseVotes,
  NULLIF(ts.ReopenVotes, 0) AS ReopenVotes,
  ba.BadgesCount,
  ba.BadgeValue,
  tg.TagName,
  ta.TagPostCount,
  ta.AvgScore,
  ta.TotalViews,
  lit.Text AS LatestBodyEdit
FROM PostStats ps
JOIN PostTypes pt ON pt.Id = ps.PostTypeId
LEFT JOIN Users u ON u.Id = ps.OwnerUserId
LEFT JOIN (SELECT Id, Name FROM CloseReasonTypes) pc ON pc.Id = (SELECT CAST(Comment AS int) FROM PostHistory ph WHERE ph.PostId = ps.Id AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC LIMIT 1)
LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) pcId ON pcId.Id = 10
LEFT JOIN TopContributors ba ON ba.UserId = ps.OwnerUserId
LEFT JOIN PostLinks pl ON pl.PostId = ps.Id
LEFT JOIN TagActivity ta ON ta.TagName = ANY(string_to_array(ps.Tags, '><'))
LEFT JOIN (SELECT Text, PostId FROM LatestUserEdit) lit ON lit.PostId = ps.Id
WHERE ps.CreationDate >= (CURRENT_DATE - INTERVAL '365 days')
ORDER BY ps.Score DESC, ps.ViewCount DESC
LIMIT 100;