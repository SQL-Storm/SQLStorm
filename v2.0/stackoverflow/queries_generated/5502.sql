-- {"query": "5502.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 807} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
),
PostHistoryAgg AS (
  SELECT
    ph.PostId,
    MAX(CASE WHEN pht.Name = 'Post Reopened' THEN 1 ELSE 0 END) AS ReopenedFlag,
    MAX(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS ClosedFlag,
    MAX(CASE WHEN ph.Text LIKE '%duplicate%' THEN 1 ELSE 0 END) AS DuplicateFlag,
    COUNT(*) AS HistoryEvents
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  GROUP BY ph.PostId
),
JoinedData AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.Title,
    rap.Tags,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.CommentCount,
    rap.AnswerCount,
    rap.FavoriteCount,
    rap.ParentId,
    rap.AcceptedAnswerId,
    tru.DisplayName AS OwnerDisplayName,
    tru.Reputation,
    tru.rn AS UserRank,
    ts.TagName,
    ts.TagCount,
    ts.AvgPostScore,
    ts.TotalViews,
    pha.ReopenedFlag,
    pha.ClosedFlag,
    pha.DuplicateFlag,
    pha.HistoryEvents
  FROM RecentActivePosts rap
  LEFT JOIN TopUsers tru ON rap.OwnerUserId = tru.UserId
  LEFT JOIN PostHistoryAgg pha ON rap.Id = pha.PostId
  LEFT JOIN (
    SELECT
      t.TagName,
      t.ExcerptPostId
    FROM Tags t
  ) tg ON rap.Id = tg.ExcerptPostId
  LEFT JOIN TagStats ts ON tg.TagName = ts.TagName
)
SELECT
  jd.PostId,
  jd.PostTypeId,
  jd.OwnerUserId,
  jd.OwnerDisplayName,
  jd.Title,
  jd.Tags,
  jd.CreationDate,
  jd.LastActivityDate,
  jd.Score,
  jd.ViewCount,
  jd.CommentCount,
  jd.AnswerCount,
  jd.FavoriteCount,
  jd.ParentId,
  jd.AcceptedAnswerId,
  jd.Reputation,
  jd.UserRank,
  jd.TagName,
  jd.TagCount,
  jd.AvgPostScore,
  jd.TotalViews,
  jd.ReopenedFlag,
  jd.ClosedFlag,
  jd.DuplicateFlag,
  jd.HistoryEvents
FROM JoinedData jd
ORDER BY jd.LastActivityDate DESC, jd.Score DESC
LIMIT 100;