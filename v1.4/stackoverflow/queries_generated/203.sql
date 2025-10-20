-- {"query": "203.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 11809} 
WITH UserStats AS (
  SELECT
    u.Id AS UserId,
    CONCAT(u.DisplayName, ' [', u.Reputation, ']') AS DisplayLabel,
    u.Reputation AS Reputation,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
    (
      SELECT t2.tag
      FROM (
        SELECT t.tag, COUNT(*) AS cnt
        FROM Posts p2
        CROSS JOIN LATERAL unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS t(tag)
        WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
        GROUP BY t.tag
        ORDER BY cnt DESC, t.tag
        LIMIT 1
      ) AS t2
    ) AS TopQuestionTag,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p3 ON p3.Id = v.PostId WHERE p3.OwnerUserId = u.Id AND v.VoteTypeId = 2) AS UpVotesReceived,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p4 ON p4.Id = v.PostId WHERE p4.OwnerUserId = u.Id AND v.VoteTypeId = 3) AS DownVotesReceived
  FROM Users u
)
SELECT
  UserId,
  DisplayLabel,
  Reputation,
  QuestionCount,
  AnswerCount,
  BadgeCount,
  LastPostDate,
  COALESCE(TopQuestionTag, 'NoTag') AS TopQuestionTag,
  UpVotesReceived,
  DownVotesReceived,
  ReputationRank
FROM UserStats
UNION ALL
SELECT
  UserId,
  DisplayLabel || ' (bench)' AS DisplayLabel,
  Reputation,
  QuestionCount,
  AnswerCount,
  BadgeCount,
  LastPostDate,
  COALESCE(TopQuestionTag, 'NoTag') AS TopQuestionTag,
  UpVotesReceived + 1,
  DownVotesReceived,
  ReputationRank
FROM UserStats
WHERE LastPostDate IS NOT NULL
ORDER BY ReputationRank, UserId
LIMIT 200;