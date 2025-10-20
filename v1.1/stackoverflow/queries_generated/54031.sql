-- {"query": "54031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2215} 
WITH QuestionScore AS (
  SELECT
    p.Id AS QuestionId,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
             WHEN v.VoteTypeId = 3 THEN -1
             ELSE 0 END) AS QuestionScore
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Tags, p.OwnerUserId, p.LastActivityDate
), 
TagScoring AS (
  SELECT
    t.tag,
    SUM(q.QuestionScore) AS TotalScore,
    COUNT(*) AS QuestionCount,
    MAX(q.LastActivityDate) AS MostRecent
  FROM (
    SELECT QuestionId, Tags, OwnerUserId, LastActivityDate, QuestionScore
    FROM QuestionScore
  ) q
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(tag)
  GROUP BY t.tag
),
UserTagScore AS (
  SELECT
    q.Tags AS Tag,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
             WHEN v.VoteTypeId = 3 THEN -1
             ELSE 0 END) AS UserScore,
    ROW_NUMBER() OVER (PARTITION BY q.Tags ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                                                          WHEN v.VoteTypeId = 3 THEN -1
                                                          ELSE 0 END) DESC) AS rn
  FROM Posts q
  JOIN Votes v ON v.PostId = q.Id
  JOIN Users u ON u.Id = q.OwnerUserId
  WHERE q.PostTypeId = 1
  GROUP BY q.Tags, u.Id, u.DisplayName, u.Reputation
)
SELECT
  ts.tag,
  ts.TotalScore,
  ts.QuestionCount,
  ts.MostRecent,
  ut.UserId,
  ut.DisplayName,
  ut.Reputation
FROM TagScoring ts
LEFT JOIN UserTagScore ut ON ut.Tag = ts.tag AND ut.rn = 1
ORDER BY ts.TotalScore DESC
LIMIT 20;