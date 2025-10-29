-- {"query": "5732.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1000} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.LastAccessDate,
    u.WebsiteUrl,
    u.EmailHash,
    u.AccountId,
    -- window function: running total of scores by Owner within 180 days of creation
    SUM(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScoreByOwner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= (CURRENT_DATE - INTERVAL '2 years')
),
CorrelatedStats AS (
  SELECT
    rp.*,
    (SELECT COUNT(*) FROM Posts AS child WHERE child.ParentId = rp.Id) AS AnswerCountFromChildren,
    (SELECT AVG(Comments.Score) FROM Comments AS Comments WHERE Comments.PostId = rp.Id) AS AvgCommentScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpModCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 4) AS OffensiveVoteCount
  FROM RankedPosts rp
),
Combined AS (
  SELECT
    cs.Id,
    cs.Title,
    cs.CreationDate,
    cs.Score,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.Tags,
    cs.AnswerCount,
    cs.CommentCount,
    cs.LastActivityDate,
    cs.PostTypeId,
    cs.FavoriteCount,
    cs.ContentLicense,
    cs.OwnerDisplayName,
    cs.Reputation,
    cs.OwnerCreationDate,
    cs.Location,
    cs.Views,
    cs.UpVotes,
    cs.DownVotes,
    cs.LastAccessDate,
    cs.WebsiteUrl,
    cs.EmailHash,
    cs.AccountId,
    cs.CumulativeScoreByOwner,
    COALESCE(cs.AnswerCountFromChildren, 0) AS AnswerCountFromChildren,
    COALESCE(cs.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(cs.UpModCount, 0) AS UpModCount,
    COALESCE(cs.OffensiveVoteCount, 0) AS OffensiveVoteCount
  FROM CorrelatedStats cs
),
Filtered AS (
  SELECT
    *
  FROM Combined
  WHERE OwnerUserId IS NOT NULL
    AND (Score > 0 OR ViewCount > 100)
    AND (Tags LIKE '%<sql>%'
         OR Tags LIKE '%<performance>%'
         OR Tags LIKE '%<benchmark>%')
),
Joins AS (
  SELECT
    f.*,
    ld.Name AS LastEditorName,
    lh.Name AS HistoryTag
  FROM Filtered f
  LEFT JOIN PostHistory ph ON ph.PostId = f.Id
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  LEFT JOIN Users lu ON f.LastEditorUserId = lu.Id
  LEFT JOIN (VALUES ('2020-01-01','2020-12-31'), ('2021-01-01','2021-12-31')) AS t(start_date, end_date) 
    ON 1=1
  LEFT JOIN Titles ld ON 1=1 -- placeholder for optional aliasing in complex query
)
SELECT
  Id,
  Title,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  Tags,
  AnswerCount,
  CommentCount,
  LastActivityDate,
  PostTypeId,
  FavoriteCount,
  ContentLicense,
  OwnerDisplayName,
  Reputation,
  OwnerCreationDate,
  Location,
  Views,
  UpVotes,
  DownVotes,
  LastAccessDate,
  WebsiteUrl,
  EmailHash,
  AccountId,
  CumulativeScoreByOwner,
  AnswerCountFromChildren,
  AvgCommentScore,
  UpModCount,
  OffensiveVoteCount
FROM Joins
ORDER BY CumulativeScoreByOwner DESC, Score DESC, ViewCount DESC
LIMIT 100;