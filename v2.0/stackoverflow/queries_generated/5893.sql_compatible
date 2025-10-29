WITH
_recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
_annotated AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.LastActivityDate,
    q.AcceptedAnswerId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    COALESCE(bg.Class, 0) AS GoldBadgeClass,
    ARRAY_AGG(DISTINCT tg.TagName) AS TagNames
  FROM _recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Badges bg ON bg.UserId = u.Id AND bg.Class = 1
  -- removed the no-op derived table and fix lateral unnest to be standard where supported
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(REPLACE(REPLACE(q.Tags, '<', ''), '>', ''), '><')) AS TagName
  ) AS tg
  GROUP BY
    q.PostId, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount,
    q.OwnerUserId, q.LastActivityDate, q.AcceptedAnswerId, u.DisplayName, u.Reputation, u.Location, COALESCE(bg.Class, 0)
),
_with_links AS (
  SELECT
    a.PostId AS QuestionId,
    a.Title,
    a.OwnerDisplayName,
    a.Reputation,
    a.Location,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.TagNames,
    a.GoldBadgeClass,
    COALESCE(closed.CountClosed, 0) AS ClosedVotes
  FROM _annotated a
  LEFT JOIN (
    SELECT ph.PostId, COUNT(*) AS CountClosed
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE pht.Name LIKE '%Close%' OR pht.Id = 10
    GROUP BY ph.PostId
  ) AS closed ON closed.PostId = a.PostId
),
_metrics AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.OwnerDisplayName,
    q.Reputation,
    q.Location,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.TagNames,
    q.GoldBadgeClass,
    q.ClosedVotes,
    ROW_NUMBER() OVER (
      ORDER BY q.LastActivityDate DESC, q.ViewCount DESC, q.Score DESC
    ) AS rn_by_activity
  FROM _with_links q
)
SELECT
  QuestionId,
  Title,
  OwnerDisplayName,
  Reputation,
  Location,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  TagNames,
  GoldBadgeClass,
  ClosedVotes,
  rn_by_activity AS rank_hint
FROM _metrics
WHERE rn_by_activity <= 100
ORDER BY LastActivityDate DESC, ViewCount DESC, Score DESC;