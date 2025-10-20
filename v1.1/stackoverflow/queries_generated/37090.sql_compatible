WITH
ActivityScore AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    COALESCE(p.Score,0) * 4.0
      + COALESCE(p.ViewCount,0) * 0.02
      + COALESCE(p.AnswerCount,0) * 6.0
      + COALESCE(p.CommentCount,0) * 1.5
      + (CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 25 ELSE 0 END) AS BasePopularity,
    EXP(-EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - COALESCE(p.LastActivityDate,p.CreationDate))) / (60.0*60*24*90)) AS RecencyFactor
  FROM Posts p
),
HistoryMetrics AS (
  SELECT
    ph.PostId,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)) AS EditCount,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenCount,
    MAX(ph.CreationDate) AS LastHistoryDate,
    COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS DistinctEditors
  FROM PostHistory ph
  GROUP BY ph.PostId
),
VoteMetrics AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
    COUNT(DISTINCT v.UserId) AS DistinctVoters,
    SUM(CASE WHEN v.VoteTypeId IN (2,5) THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetPositiveVotes
  FROM Votes v
  GROUP BY v.PostId
),
TagExplode AS (
  SELECT
    p.Id AS PostId,
    trim(both '<>' FROM unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><'))) AS Tag
  FROM Posts p
  WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
TagAggregates AS (
  SELECT
    te.Tag,
    COUNT(*) AS QuestionsWithTag,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted
  FROM TagExplode te
  JOIN Posts p ON p.Id = te.PostId
  GROUP BY te.Tag
),
UserMetrics AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COALESCE(b.BadgeScore,0) AS BadgeScore,
    COALESCE(up.PostCount,0) AS PostCount,
    COALESCE(up.AvgScore,0) AS AvgPostScore
  FROM Users u
  LEFT JOIN (
    SELECT UserId, SUM(CASE Class WHEN 1 THEN 10 WHEN 2 THEN 5 WHEN 3 THEN 1 ELSE 0 END) AS BadgeScore
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostCount, AVG(COALESCE(Score,0)) AS AvgScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) up ON up.OwnerUserId = u.Id
),
PostScore AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    COALESCE(a.BasePopularity,0) AS BasePopularity,
    COALESCE(a.RecencyFactor,1) AS RecencyFactor,
    COALESCE(h.EditCount,0) AS EditCount,
    COALESCE(h.DistinctEditors,0) AS DistinctEditors,
    COALESCE(v.UpVotes,0) AS UpVotes,
    COALESCE(v.DownVotes,0) AS DownVotes,
    COALESCE(v.Favorites,0) AS Favorites,
    COALESCE(v.DistinctVoters,0) AS DistinctVoters,
    COALESCE(tm.TopTag, '') AS TopTag,
    (
      COALESCE(a.BasePopularity,0) * COALESCE(a.RecencyFactor,1) * 1.0
      + (COALESCE(v.NetPositiveVotes,0) * 8.0)
      + (LEAST(COALESCE(h.EditCount,0),25) * 2.5)
      + (COALESCE(h.DistinctEditors,0) * 4.0)
      + (COALESCE(u.Reputation,0) / 1000.0) * 5.0
      + (COALESCE(ta.QuestionsWithTag,0) / NULLIF(GREATEST(1, (SELECT MAX(QuestionsWithTag) FROM TagAggregates)),0)) * 10.0
    ) AS CompositeScore
  FROM Posts p
  LEFT JOIN ActivityScore a ON a.PostId = p.Id
  LEFT JOIN HistoryMetrics h ON h.PostId = p.Id
  LEFT JOIN VoteMetrics v ON v.PostId = p.Id
  LEFT JOIN UserMetrics u ON u.UserId = p.OwnerUserId
  LEFT JOIN (
    SELECT te.PostId, te.Tag AS TopTag
    FROM (
      SELECT te.PostId, te.Tag, ROW_NUMBER() OVER (PARTITION BY te.PostId ORDER BY tg.Count DESC NULLS LAST, te.Tag) AS rn
      FROM TagExplode te
      LEFT JOIN Tags tg ON tg.TagName = te.Tag
    ) te
    WHERE te.rn = 1
  ) tm ON tm.PostId = p.Id
  LEFT JOIN TagAggregates ta ON ta.Tag = tm.TopTag
),
Clustered AS (
  SELECT
    ps.Id,
    ps.Title,
    ps.PostTypeId,
    ps.OwnerUserId,
    ps.BasePopularity,
    ps.RecencyFactor,
    ps.EditCount,
    ps.DistinctEditors,
    ps.UpVotes,
    ps.DownVotes,
    ps.Favorites,
    ps.DistinctVoters,
    ps.TopTag,
    ps.CompositeScore,
    ROW_NUMBER() OVER (PARTITION BY ps.PostTypeId ORDER BY ps.CompositeScore DESC) AS RankByType,
    NTILE(100) OVER (ORDER BY ps.CompositeScore DESC) AS PercentileBucket
  FROM PostScore ps
  WHERE ps.CompositeScore IS NOT NULL
)
SELECT
  c.Id AS PostId,
  c.PostTypeId,
  c.Title,
  c.OwnerUserId,
  c.BasePopularity,
  ROUND(c.RecencyFactor,6) AS RecencyFactor,
  c.EditCount,
  c.DistinctEditors,
  c.UpVotes,
  c.DownVotes,
  c.Favorites,
  c.DistinctVoters,
  c.TopTag,
  ROUND(c.CompositeScore,4) AS CompositeScore,
  c.RankByType,
  c.PercentileBucket
FROM Clustered c
WHERE c.PercentileBucket <= 5
  AND (c.EditCount >= 3 OR c.DistinctEditors >= 2 OR c.UpVotes >= 5)
ORDER BY c.CompositeScore DESC
LIMIT 200;