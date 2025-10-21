-- {"query": "24056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4664} 
WITH
  PostsCTE AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.CreationDate,
           p.LastActivityDate,
           p.OwnerUserId,
           p.PostTypeId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  AnswersCTE AS (
    SELECT p.Id,
           p.ParentId AS QuestionId,
           p.Score,
           p.CreationDate,
           p.LastActivityDate,
           p.OwnerUserId,
           p.PostTypeId
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  FirstLastEdit AS (
    SELECT ph.PostId,
           MIN(ph.CreationDate) AS FirstEdit,
           MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
    GROUP BY ph.PostId
  ),
  VoteScore AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1
                    ELSE 0 END) AS NetVotes,
           COUNT(DISTINCT v.UserId) AS VoterCount,
           DATE_TRUNC('day', v.CreationDate) AS VoteDay
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
    GROUP BY v.PostId, VoteDay
  ),
  TagExplode AS (
    SELECT p.Id,
           unnest(string_to_array(
              regexp_replace(p.Tags,'^&lt;|&gt;$','', 'g'), '><')) AS TagName,
           ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY NULL) AS TagOrder
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  TagStats AS (
    SELECT TagName,
           COUNT(*) AS TotalPostsWithTag,
           RANK() OVER (ORDER BY COUNT(*) DESC) AS OverallTagRank
    FROM TagExplode
    GROUP BY TagName
  ),
  UserRep AS (
    SELECT u.Id,
           u.Reputation,
           LAG(u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS PrevRep,
           CASE WHEN u.Reputation > LAG(u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.CreationDate)
                THEN 'Up' ELSE 'Down' END AS RepTrend
    FROM Users u
  ),
  CommentCounts AS (
    SELECT c.PostId,
           COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
  )
SELECT
  p.Id AS PostId,
  p.Title,
  p.Score,
  p.CreationDate,
  p.LastActivityDate,
  COALESCE(fe.FirstEdit, p.CreationDate) AS FirstEditDate,
  fe.LastEdit,
  vs.NetVotes,
  vs.VoterCount,
  vs.VoteDay,
  te.TagName,
  ts.TotalPostsWithTag,
  ts.OverallTagRank,
  u.Reputation AS CurrentRep,
  u.PrevRep,
  u.RepTrend,
  cc.CommentCount,
  'Question' AS PostType,
  p.PostTypeId
FROM PostsCTE p
LEFT JOIN FirstLastEdit fe ON fe.PostId = p.Id
LEFT JOIN VoteScore vs ON vs.PostId = p.Id
LEFT JOIN TagExplode te ON te.Id = p.Id
LEFT JOIN TagStats ts ON ts.TagName = te.TagName
LEFT JOIN UserRep u ON u.Id = p.OwnerUserId
LEFT JOIN CommentCounts cc ON cc.PostId = p.Id
WHERE p.CreationDate >= DATE '2023-01-01'
  AND (te.TagOrder = 1 OR te.TagOrder IS NULL)
  AND NOT EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10)
  AND p.Score > COALESCE((SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1), 0)
UNION ALL
SELECT
  a.Id AS PostId,
  NULL AS Title,
  a.Score,
  a.CreationDate,
  a.LastActivityDate,
  NULL AS FirstEditDate,
  NULL AS LastEdit,
  vs.NetVotes,
  vs.VoterCount,
  vs.VoteDay,
  NULL AS TagName,
  NULL AS TotalPostsWithTag,
  NULL AS OverallTagRank,
  u.Reputation AS CurrentRep,
  u.PrevRep,
  u.RepTrend,
  cc.CommentCount,
  'Answer' AS PostType,
  a.PostTypeId
FROM AnswersCTE a
LEFT JOIN FirstLastEdit fe ON fe.PostId = a.Id
LEFT JOIN VoteScore vs ON vs.PostId = a.Id
LEFT JOIN TagExplode te ON te.Id = a.Id
LEFT JOIN TagStats ts ON ts.TagName = te.TagName
LEFT JOIN UserRep u ON u.Id = a.OwnerUserId
LEFT JOIN CommentCounts cc ON cc.PostId = a.Id
WHERE a.CreationDate >= DATE '2023-01-01'
  AND NOT EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = a.Id AND ph.PostHistoryTypeId = 10)
  AND a.Score > COALESCE((SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2), 0)
ORDER BY CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10000 ROWS ONLY;