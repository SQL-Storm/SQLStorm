-- {"query": "36034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 532} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  COALESCE(a.CountAnswer, 0) AS AnswerCount,
  COALESCE(v.UpVoteCount, 0) AS UpVotes,
  COALESCE(v.DownVoteCount, 0) AS DownVotes,
  p.Tags,
  p.LastActivityDate,
  p.FavoriteCount,
  p.ParentId,
  p.AcceptedAnswerId,
  bh.LastHistoryType,
  bh.HistoryEventCount,
  cl.Name AS CloseReason
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS CountAnswer
  FROM Posts
  WHERE PostTypeId = 2 -- Answers
  GROUP BY PostId
) a ON p.Id = a.PostId
LEFT JOIN (
  SELECT
    PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
  FROM Votes
  GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN (
  SELECT
    PostId,
    MAX(LastEditDate) AS LastActivityDate
  FROM Posts
  GROUP BY PostId
) la ON p.Id = la.PostId
LEFT JOIN (
  SELECT
    PostHistory.PostId,
    MAX(PostHistory.CreationDate) AS LastHistoryDate,
    MAX(PostHistory.Id) AS LastHistoryId,
    MAX(CASE WHEN PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS LastHistoryType,
    COUNT(*) AS HistoryEventCount
  FROM PostHistory
  GROUP BY PostHistory.PostId
) bh ON p.Id = bh.PostId
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN CloseReasonTypes cl ON CAST(ph.Comment AS VARCHAR(100)) LIKE '%' || cl.Id || '%'
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate >= NOW() - INTERVAL '365 days'
ORDER BY p.ViewCount DESC, p.Score DESC
LIMIT 100;