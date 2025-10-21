WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner_activity
  FROM Posts p
  WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days')
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE t.IsModeratorOnly = FALSE
  GROUP BY t.TagName, t.Count, u.Id, u.DisplayName, u.Reputation
),
AmbiguousLinks AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.RelatedPostId IS NOT NULL
    AND pl.PostId <> pl.RelatedPostId
),
ActiveQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
),
ComplexSummary AS (
  SELECT
    aq.Id AS QuestionId,
    aq.Title AS QuestionTitle,
    uq.DisplayName AS OwnerName,
    uq.Reputation AS OwnerRep,
    aq.Score AS QuestionScore,
    aq.ViewCount AS Views,
    aq.AnswerCount,
    qc.LastCloseReason,
    COALESCE(vr.avg_ver, 0) AS AvgRevisionLatency
  FROM ActiveQuestions aq
  LEFT JOIN Users uq ON uq.Id = aq.OwnerUserId
  LEFT JOIN (
    SELECT p.Id, AVG((EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) / 3600.0)) AS avg_ver
    FROM Posts p
    GROUP BY p.Id
  ) vr ON vr.Id = aq.Id
  LEFT JOIN (
    SELECT ph.PostId, ph.Comment AS LastCloseReason
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    ORDER BY ph.CreationDate DESC
  ) qc ON qc.PostId = aq.Id
)
SELECT
  cs.QuestionId,
  cs.QuestionTitle,
  cs.OwnerName,
  cs.OwnerRep,
  cs.QuestionScore,
  cs.Views,
  cs.AnswerCount,
  cs.LastCloseReason,
  cs.AvgRevisionLatency,
  ar.Title AS RecentTitle,
  ar.LastActivityDate AS RecentActivityDate,
  ar.rn_owner_activity
FROM ComplexSummary cs
LEFT JOIN RecentActivity ar ON ar.PostId = cs.QuestionId
LEFT JOIN AmbiguousLinks al ON al.PostId = cs.QuestionId
LEFT JOIN TagStats ts ON ts.TagName = ANY(string_to_array(REPLACE(REPLACE(cs.QuestionTitle, '<',''), '>', ''), ' '))
WHERE cs.AvgRevisionLatency IS NOT NULL
ORDER BY cs.Views DESC, cs.QuestionScore DESC
LIMIT 100;