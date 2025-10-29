-- {"query": "5563.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 660} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 0
),
TagSummaries AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT
  -- Combine popular questions with their top editors and tag summaries
  r.PostId,
  r.Title AS QuestionTitle,
  r.Tags,
  r.CreationDate AS QuestionCreationDate,
  r.Score AS QuestionScore,
  r.ViewCount AS QuestionViewCount,
  u.UserId AS EditorUserId,
  u.DisplayName AS EditorDisplayName,
  u.Reputation AS EditorReputation,
  u.LastAccessDate AS EditorLastAccessDate,
  t.TagName AS TopTag,
  s.Count AS TagCount,
  s.ExcerptPostId,
  s.WikiPostId,
  h.Name AS HistoryTypeName
FROM RecentHot r
LEFT JOIN Posts a ON a.Id = r.PostId
LEFT JOIN Votes v ON v.PostId = r.PostId
LEFT JOIN Users u ON u.Id = a.LastEditorUserId
LEFT JOIN (SELECT TOP 1 TagName, Count, ExcerptPostId, WikiPostId
           FROM TagSummaries
           WHERE rn = 1) s ON s.ExcerptPostId = r.PostId
LEFT JOIN PostHistory ph ON ph.PostId = r.PostId
LEFT JOIN PostHistoryTypes h ON h.Id = ph.PostHistoryTypeId
LEFT JOIN LATERAL (
  SELECT tt.Name AS TopTag
  FROM PostLinks pl
  JOIN Tags tt ON tt.Id = (
      SELECT Id FROM Tags t2
      WHERE t2.IsModeratorOnly = 0
        AND POSITION('<' || t2.TagName || '>' IN r.Tags) > 0
      LIMIT 1
  )
  WHERE pl.PostId = r.PostId AND pl.LinkTypeId = 3
  LIMIT 1
) AS taghint ON true
WHERE r.rn <= 50
ORDER BY r.LastActivityDate DESC, r.Score DESC
OFFSET 0 ROWS
FETCH NEXT 50 ROWS ONLY;