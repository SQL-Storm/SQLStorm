-- {"query": "5088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 695} 
WITH RecentActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tagname ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY QuestionCount DESC
  LIMIT 50
),
TagPopulation AS (
  SELECT
    tt.TagName,
    tt.QuestionCount,
    tt.AvgScore,
    tt.MaxViews,
    u.Reputation,
    u.DisplayName
  FROM TopTags tt
  LEFT JOIN LATERAL (
    SELECT DISTINCT ON (p.OwnerUserId) p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%' || tt.TagName || '%'
    ORDER BY p.OwnerUserId, p.LastActivityDate DESC
  ) AS x(owner) ON true
  LEFT JOIN Users u ON u.Id = x.owner
)
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.Tags,
  q.OwnerUserId AS OwnerId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  q.CreationDate,
  q.LastActivityDate,
  q.ViewCount,
  q.Score,
  COALESCE(vt.UpMod, 0) AS UpVotes,
  COALESCE(vt.DownMod, 0) AS DownVotes,
  pc.CloseReason,
  json_build_object(
    'question_owner_follows', CASE WHEN u.Reputation > 10000 THEN true ELSE false END,
    'recent_activity_days_ago', EXTRACT(DAY FROM NOW() - q.LastActivityDate)
  ) AS Metadata
FROM (
  SELECT p.Id, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
) AS q
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN (
  SELECT ph.PostId,
         ph.Comment AS CloseReason,
         ph.CreationDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10
) AS pc ON pc.PostId = q.Id
LEFT JOIN (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpMod,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownMod
  FROM Votes
  GROUP BY PostId
) AS vt ON vt.PostId = q.Id
ORDER BY q.LastActivityDate DESC
LIMIT 100;