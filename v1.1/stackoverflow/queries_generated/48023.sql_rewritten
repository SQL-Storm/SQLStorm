-- {"query": "48023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 528} 
SELECT
  u.DisplayName,
  u.Reputation,
  COUNT(CASE WHEN pt.Name = 'Question' THEN 1 ELSE NULL END) AS QuestionCount,
  COUNT(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE NULL END) AS AnswerCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
  AVG(CASE WHEN pt.Name = 'Question' THEN p.Score ELSE NULL END) AS AvgQuestionScore,
  AVG(CASE WHEN pt.Name = 'Answer' THEN p.Score ELSE NULL END) AS AvgAnswerScore,
  MAX(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE NULL END) AS MaxQuestionViewCount,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Posts AS p_inner
    WHERE
      p_inner.OwnerUserId = u.Id AND p_inner.ClosedDate IS NOT NULL
  ) AS ClosedPostCount,
  (
    SELECT
      AVG(Score)
    FROM Comments AS c_inner
    WHERE
      c_inner.UserId = u.Id
  ) AS AvgCommentScore,
  SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount
FROM Users AS u
JOIN Posts AS p
  ON u.Id = p.OwnerUserId
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Votes AS v
  ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN Badges AS b
  ON u.Id = b.UserId
LEFT JOIN PostHistory AS ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 100 AND u.Reputation > 1000
ORDER BY
  u.Reputation DESC,
  AnswerCount DESC
LIMIT 50;