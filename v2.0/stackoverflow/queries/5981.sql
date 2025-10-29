WITH top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1
),
recent_updates AS (
  SELECT
    ph.PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS HistoryUserId,
    ph.Comment,
    ph.Text,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.PostId IN (SELECT PostId FROM top_questions)
    AND ph.PostHistoryTypeId IN (10,11,12,16,36)
),
activity_window AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.Tags,
    DENSE_RANK() OVER (
      ORDER BY q.LastActivityDate DESC, q.Score DESC
    ) AS activity_rank
  FROM top_questions q
),
tag_analytics AS (
  SELECT
    t.TagName,
    COUNT(*) AS TaggedQuestions,
    AVG(q.Score) AS AvgScore,
    SUM(q.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><' )) AS TagName,
      p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) s
  JOIN Tags t ON LOWER(s.TagName) = LOWER(t.TagName)
  JOIN top_questions q ON q.PostId = s.Id
  GROUP BY t.TagName
  ORDER BY TaggedQuestions DESC
  LIMIT 5
)
SELECT
  ac.PostId,
  ac.Title,
  ac.CreationDate AS CreationDateUtc,
  ac.LastActivityDate AS LastActivityUtc,
  ac.ViewCount,
  ac.Score,
  ac.AnswerCount,
  ac.CommentCount,
  ac.FavoriteCount,
  ac.Tags,
  ac.activity_rank,
  ro.RecentOwnerDisplayName,
  ro.RecentOwnerReputation,
  hh.HistoryDate,
  hh.PostHistoryTypeId,
  hh.Comment AS HistoryComment,
  ah.TagName AS TopTag
FROM activity_window ac
LEFT JOIN (
  SELECT
    p.Id,
    u.DisplayName AS RecentOwnerDisplayName,
    u.Reputation AS RecentOwnerReputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate = (
    SELECT MAX(p2.LastActivityDate) FROM Posts p2 WHERE p2.Id = p.Id
  )
) ro ON ac.PostId = ro.Id
LEFT JOIN (
  SELECT
    p.Id,
    u.DisplayName AS RecentOwnerDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.Id IN (SELECT PostId FROM recent_updates)
) wu ON ac.PostId = wu.Id
LEFT JOIN recent_updates hh ON ac.PostId = hh.PostId
LEFT JOIN (SELECT DISTINCT TagName FROM tag_analytics) ah ON TRUE
ORDER BY ac.activity_rank
LIMIT 100;