-- {"query": "24082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4453} 
WITH
UserStats AS (
  SELECT u.Id   AS UserId,
         u.DisplayName,
         COALESCE(u.Reputation,0) AS Reputation,
         COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
         COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END),0) AS Acceptances,
         MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v      ON v.PostId      = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestion AS (
  SELECT p.OwnerUserId,
         p.Id   AS PostId,
         p.Title,
         p.Score,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ClosedCount AS (
  SELECT ph.PostId, COUNT(*) AS ClosedCnt
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10          -- closed
  GROUP BY ph.PostId
),
ReopenCount AS (
  SELECT ph.PostId, COUNT(*) AS ReopenCnt
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 11          -- reopened
  GROUP BY ph.PostId
)
SELECT us.UserId,
       us.DisplayName,
       us.Reputation,
       us.QuestionCount,
       us.AnswerCount,
       us.UpVotes,
       us.DownVotes,
       us.Acceptances,
       tq.Title          AS TopQuestionTitle,
       tq.Score          AS TopQuestionScore,
       COALESCE(cc.ClosedCnt,0)   AS ClosedCount,
       COALESCE(rc.ReopenCnt,0)   AS ReopenedCount,
       ( SELECT COUNT(DISTINCT tag) 
         FROM ( 
                SELECT unnest(string_to_array(
                               substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
                FROM Posts p
                WHERE p.OwnerUserId = us.UserId
                  AND p.PostTypeId = 1
                  AND p.Tags IS NOT NULL
              ) AS tags(subtag) ) AS DistinctTagCount,
       CASE
         WHEN EXISTS( SELECT 1
                      FROM PostHistory ph
                      WHERE ph.PostId = tq.PostId
                        AND ph.PostHistoryTypeId = 10
                        AND ph.Comment::int = 101 )  -- duplicate close reason
         THEN 1
         ELSE 0
       END AS IsDuplicateClosed
FROM UserStats us
LEFT JOIN TopQuestion tq   ON tq.OwnerUserId = us.UserId AND tq.rn = 1
LEFT JOIN ClosedCount cc   ON cc.PostId   = tq.PostId
LEFT JOIN ReopenCount rc   ON rc.PostId   = tq.PostId
ORDER BY us.Reputation DESC, us.UserId
LIMIT 10;