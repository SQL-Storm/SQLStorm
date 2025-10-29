-- {"query": "5499.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 734} 
WITH TopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    COUNT(a.Id) AS AnswerCount
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  WHERE p.PostTypeId = 1
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, p.Tags, p.LastActivityDate
),
ExtendedStats AS (
  SELECT
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.ViewCount,
    tq.Score,
    tq.OwnerUserId,
    tq.Tags,
    tq.LastActivityDate,
    tq.AnswerCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    v.UpModCount,
    v.DownModCount,
    v.BountyCount,
    ht.Name AS HistoryType,
    pt.Name AS PostTypeName
  FROM TopQuestions tq
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = tq.QuestionId
  LEFT JOIN Users u ON u.Id = tq.OwnerUserId
  LEFT JOIN PostHistory ph ON ph.PostId = tq.QuestionId
  LEFT JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
  LEFT JOIN PostTypes pt ON pt.Id = 1
  WHERE tq.AnswerCount >= 0
),
CorrelatedTags AS (
  SELECT
    es.QuestionId,
    es.Title,
    es.CreationDate,
    es.ViewCount,
    es.Score,
    es.OwnerUserId,
    es.Tags,
    es.LastActivityDate,
    es.AnswerCount,
    es.Reputation,
    es.DisplayName,
    es.Location,
    es.UpModCount,
    es.DownModCount,
    es.BountyCount,
    es.HistoryType,
    es.PostTypeName,
    t.TagName
  FROM ExtendedStats es
  LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(substr(es.Tags, 2, length(es.Tags)-2), '><')) AS TagName
  ) t ON true
)
SELECT
  cq.QuestionId,
  cq.Title,
  cq.CreationDate,
  cq.ViewCount,
  cq.Score,
  cq.OwnerUserId,
  cq.Tags,
  cq.LastActivityDate,
  cq.AnswerCount,
  cq.Reputation,
  cq.DisplayName,
  cq.Location,
  cq.UpModCount,
  cq.DownModCount,
  cq.BountyCount,
  cq.HistoryType,
  cq.PostTypeName,
  cq.TagName
FROM CorrelatedTags cq
WHERE
  cq.Reputation IS NOT NULL
  AND cq.UpModCount > 0
  AND (EXISTS (
    SELECT 1
    FROM Badges b
    WHERE b.UserId = cq.OwnerUserId
      AND b.Class = 1
  )
  )
ORDER BY cq.LastActivityDate DESC, cq.Score DESC
LIMIT 100
OFFSET 0;