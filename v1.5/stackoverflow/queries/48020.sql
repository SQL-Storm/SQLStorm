-- {"query": "48020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1004} 
WITH QuestionMetrics AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.Score AS QuestionScore,
    p.ViewCount AS QuestionViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id AND Class = 3) AS BronzeBadges,
    COUNT(a.Id) AS AnswerCountActual,
    AVG(a.Score) AS AverageAnswerScore,
    SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
  FROM Posts AS p
  JOIN Users AS u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Posts AS a
    ON p.Id = a.ParentId
  WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= '2023-01-01'
    AND p.CreationDate < '2024-01-01'
  GROUP BY
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.DisplayName,
    u.Reputation,
    u.Id
), AnswerMetrics AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(a.Id) AS TotalAnswers,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount
  FROM Posts AS a
  JOIN Posts AS p
    ON a.ParentId = p.Id
  WHERE
    a.PostTypeId = 2
  GROUP BY
    a.ParentId
), UserEngagement AS (
  SELECT
    p.Id AS QuestionId,
    COUNT(c.Id) AS QuestionCommentCount,
    COUNT(DISTINCT v.UserId) AS DistinctVoters,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
  FROM Posts AS p
  LEFT JOIN Comments AS c
    ON p.Id = c.PostId
  LEFT JOIN Votes AS v
    ON p.Id = v.PostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.Id
)
SELECT
  qm.QuestionId,
  qm.Title,
  qm.QuestionScore,
  qm.QuestionViewCount,
  qm.AnswerCount,
  qm.CommentCount,
  qm.FavoriteCount,
  qm.OwnerDisplayName,
  qm.OwnerReputation,
  qm.GoldBadges,
  qm.SilverBadges,
  qm.BronzeBadges,
  COALESCE(am.TotalAnswers, 0) AS TotalAnswers,
  COALESCE(am.AvgAnswerScore, 0) AS AvgAnswerScore,
  qm.IsAcceptedAnswerPresent,
  COALESCE(ue.QuestionCommentCount, 0) AS QuestionCommentCount,
  COALESCE(ue.DistinctVoters, 0) AS DistinctVoters,
  COALESCE(ue.UpVoteCount, 0) AS UpVoteCount,
  COALESCE(ue.DownVoteCount, 0) AS DownVoteCount,
  (
    SELECT
      COUNT(*)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = qm.QuestionId AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditCount
FROM QuestionMetrics AS qm
LEFT JOIN AnswerMetrics AS am
  ON qm.QuestionId = am.QuestionId
LEFT JOIN UserEngagement AS ue
  ON qm.QuestionId = ue.QuestionId
ORDER BY
  qm.QuestionScore DESC,
  qm.QuestionViewCount DESC
LIMIT 100;