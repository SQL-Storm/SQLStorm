-- {"query": "54077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1445} 

WITH
  RankVotes AS (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
               WHEN v.VoteTypeId = 3 THEN -1
               ELSE 0 END)          AS VoteScore,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
  ),
  RecentEdits AS (
    SELECT
      ph.PostId,
      MAX(ph.CreationDate)                               AS LastEdit,
      DATEDIFF(day, MAX(ph.CreationDate), GETDATE()) AS DaysSinceLastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)           -- edit title/body/tags
    GROUP BY ph.PostId
  ),
  TagBreakdown AS (
    SELECT
      p.Id   AS PostId,
      t.TagName,
      RANK() OVER (PARTITION BY p.Id ORDER BY t.Count DESC) AS TagRank
    FROM Posts p
    JOIN Tags t
      ON t.TagName = ANY(string_to_array(p.Tags, '><'))
  ),
  CommentStats AS (
    SELECT
      c.PostId,
      COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
  ),
  TopUpvoter AS (
    SELECT
      v.PostId,
      v.UserId                      AS UpvoterId,
      ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS RN
    FROM Votes v
    WHERE v.VoteTypeId = 2          -- upvote
  )
SELECT
  p.Id               AS PostId,
  p.Title,
  p.OwnerUserId,
  u.Reputation,
  rv.VoteScore,
  rv.UpVotes,
  rv.DownVotes,
  cs.CommentCount,
  pt.FavoriteCount,
  re.LastEdit,
  re.DaysSinceLastEdit,
  db.TagName         AS FirstTag,
  tuv.UpvoterId      AS MostRecentUpvoter,
  ph.CreationDate    AS LastDeletionTimestamp
FROM Posts p
LEFT JOIN Users u                        ON u.Id = p.OwnerUserId
LEFT JOIN RankVotes rv                   ON rv.PostId = p.Id
LEFT JOIN RecentEdits re                 ON re.PostId = p.Id
LEFT JOIN TagBreakdown db                ON db.PostId = p.Id AND db.TagRank = 1
LEFT JOIN CommentStats cs                ON cs.PostId = p.Id
LEFT JOIN TopUpvoter tuv                ON tuv.PostId = p.Id AND tuv.RN = 1
LEFT JOIN PostHistory ph                ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 12   -- deleted
LEFT JOIN (
      SELECT PostId, COUNT(*) AS FavoriteCount
      FROM Votes
      WHERE VoteTypeId = 5
      GROUP BY PostId
) pt                                  ON pt.PostId = p.Id
WHERE p.PostTypeId = 1                -- questions only
  AND rv.VoteScore > 100              -- high scoring
  AND db.TagName = 'sql'               -- specific tag filter
ORDER BY rv.VoteScore DESC,
         re.DaysSinceLastEdit ASC
LIMIT 50;
