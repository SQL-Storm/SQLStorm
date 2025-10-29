-- {"query": "5599.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 760} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
TagPopularity AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    SUM(p.Score) AS total_score,
    SUM(p.ViewCount) AS total_views,
    COUNT(*) AS cnt
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY 1
),
TopTagAS AS (
  SELECT
    t.tag,
    t.total_score,
    t.total_views,
    t.cnt,
    ROW_NUMBER() OVER (ORDER BY t.total_score DESC, t.total_views DESC) AS rn
  FROM TagPopularity t
)
SELECT
  r.PostId,
  r.Title,
  r.Tags,
  r.ViewCount,
  r.Score,
  r.CreationDate,
  r.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = r.PostId) AS AnswerCount,
  (SELECT ARRAY_AGG(v.UserId) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 6) AS CloseVoters,
  (SELECT vg.Name
     FROM Votes v
     JOIN VoteTypes vg ON vg.Id = v.VoteTypeId
     WHERE v.PostId = r.PostId AND v.VoteTypeId = 2
     ORDER BY v.CreationDate DESC
     LIMIT 1) AS LastUpvotedBy,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) AS LinkCount,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = r.PostId AND vv.VoteTypeId = 2) - (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = r.PostId AND vv.VoteTypeId = 3) AS NetUpDown,
  (SELECT MAX(CASE WHEN pv.Text IS NOT NULL THEN pv.Text ELSE NULL END)
     FROM PostHistory ph
     JOIN Posts p2 ON p2.Id = ph.PostId
     LEFT JOIN (SELECT Id, Text FROM PostHistory WHERE PostHistoryTypeId = 10) AS pv ON pv.Id = ph.Id
     WHERE ph.PostId = r.PostId) AS LastCloseReason,
  (SELECT JSON_AGG(JSON_BUILD_OBJECT('date', p2.CreationDate, 'type', ht.Name))
     FROM PostHistory ph
     JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
     JOIN Posts p2 ON p2.Id = ph.PostId
     WHERE ph.PostId = r.PostId
       AND ph.PostHistoryTypeId IN (10,11,16,52)
     ) AS HistoryEvents
FROM RecentTopPosts r
LEFT JOIN Users u ON u.Id = r.OwnerUserId
LEFT JOIN TopTagAS tta ON tta.rn = 1
ORDER BY r.rn
LIMIT 100;