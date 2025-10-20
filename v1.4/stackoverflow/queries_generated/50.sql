-- {"query": "50.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 899} 
WITH
RecentPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    LastEditor.DisplayName AS LastEditorDisplayName,
    LastEditor.Reputation AS LastEditorReputation,
    pc.Name AS PostHistoryStatus
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users LastEditor ON p.LastEditorUserId = LastEditor.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  LEFT JOIN CloseReasonTypes crc ON ph.Comment LIKE CONCAT('%', crc.Name, '%')
  LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) AS pc ON ph.PostHistoryTypeId = pc.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TagScore AS (
  SELECT
    t.TagName,
    t.Count,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews,
    MIN(p.CreationDate) AS FirstPostDate
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
  GROUP BY t.TagName, t.Count
),
CorrelatedStats AS (
  SELECT
    ro.Id AS PostId,
    ro.Title,
    ro.PostTypeId,
    ro.OwnerUserId,
    ro.OwnerDisplayName,
    ro.CreationDate,
    ro.LastActivityDate,
    ro.Score,
    ro.ViewCount,
    ro.AnswerCount,
    ro.CommentCount,
    ro.FavoriteCount,
    ro.Body,
    ro.Tags,
    ro.PostHistoryStatus,
    ROW_NUMBER() OVER (
      PARTITION BY ro.OwnerUserId
      ORDER BY ro.LastActivityDate DESC, ro.Score DESC
    ) AS rn_by_owner
  FROM Posts ro
  LEFT JOIN PostHistory ph ON ph.PostId = ro.Id
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  LEFT JOIN Users u ON ro.OwnerUserId = u.Id
  WHERE ro.LastActivityDate IS NOT NULL
),
WindowedStats AS (
  SELECT
    cs.*,
    SUM(cs.Score) OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS RunningOwnerScore30d,
    AVG(cs.ViewCount) OVER (PARTITION BY cs.OwnerUserId) AS AvgViewsPerOwner
  FROM CorrelatedStats cs
  WHERE cs.rn_by_owner = 1
),
FinalResult AS (
  SELECT
    w.PostId,
    w.Title,
    w.PostTypeId,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.AnswerCount,
    w.CommentCount,
    w.FavoriteCount,
    w.Body,
    w.Tags,
    w.PostHistoryStatus,
    w.RunningOwnerScore30d,
    w.AvgViewsPerOwner,
    CASE
      WHEN w.Score IS NULL THEN 0
      ELSE w.Score
    END AS SafeScore,
    CASE
      WHEN w.ViewCount IS NULL THEN 0
      ELSE w.ViewCount
    END AS SafeViews
  FROM WindowedStats w
)
SELECT
  fr.PostId,
  fr.Title,
  fr.OwnerDisplayName,
  fr.CreationDate,
  fr.LastActivityDate,
  fr.Score,
  fr.ViewCount,
  fr.AnswerCount,
  fr.CommentCount,
  fr.FavoriteCount,
  fr.Tags,
  fr.SafeScore,
  fr.SafeViews,
  fr.RunningOwnerScore30d,
  fr.AvgViewsPerOwner
FROM FinalResult fr
ORDER BY fr.LastActivityDate DESC, fr.SafeScore DESC
LIMIT 500;