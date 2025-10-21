-- {"query": "352.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24875} 
WITH
PostWithTags AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId AS UserId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.LastEditorUserId,
    p.LastActivityDate,
    COALESCE(STRING_AGG(t.TagName, ','), '') AS TagList
  FROM Posts p
  LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName) ON TRUE
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.LastEditorUserId, p.LastActivityDate
),
PostVotes AS (
  SELECT
    p.PostId,
    p.UserId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.TagList,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    (SELECT DisplayName FROM Users u WHERE u.Id = p.LastEditorUserId) AS LastEditorDisplayName
  FROM PostWithTags p
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = p.PostId
),
QPosts AS (
  SELECT pv.PostId, pv.UserId, pv.Title, pv.CreationDate, pv.Score, pv.UpVotes, pv.DownVotes, pv.CommentCount, pv.TagList, pv.LastEditorDisplayName, pv.PostTypeId
  FROM PostVotes pv
  WHERE pv.PostTypeId = 1
),
APosts AS (
  SELECT pv.PostId, pv.UserId, pv.Title, pv.CreationDate, pv.Score, pv.UpVotes, pv.DownVotes, pv.CommentCount, pv.TagList, pv.LastEditorDisplayName, pv.PostTypeId
  FROM PostVotes pv
  WHERE pv.PostTypeId = 2
),
QWithUser AS (
  SELECT q.PostId, q.Title, q.CreationDate, q.Score, q.UpVotes, q.DownVotes, q.CommentCount, q.TagList, q.LastEditorDisplayName, u.DisplayName, u.Reputation, 1 AS PostTypeFlag, q.UserId
  FROM QPosts q
  JOIN Users u ON u.Id = q.UserId
),
AWithUser AS (
  SELECT a.PostId, a.Title, a.CreationDate, a.Score, a.UpVotes, a.DownVotes, a.CommentCount, a.TagList, a.LastEditorDisplayName, u.DisplayName, u.Reputation, 2 AS PostTypeFlag, a.UserId
  FROM APosts a
  JOIN Users u ON u.Id = a.UserId
),
Unioned AS (
  SELECT * FROM QWithUser
  UNION ALL
  SELECT * FROM AWithUser
),
Ranked AS (
  SELECT
     *,
     ROW_NUMBER() OVER (PARTITION BY UserId, PostTypeFlag ORDER BY Score DESC, CreationDate DESC) AS rn
  FROM Unioned
)
SELECT
  r.UserId,
  r.DisplayName,
  r.Reputation,
  CASE r.PostTypeFlag WHEN 1 THEN 'Question' ELSE 'Answer' END AS PostType,
  r.PostId,
  r.Title,
  r.CreationDate,
  r.Score,
  r.UpVotes,
  r.DownVotes,
  r.CommentCount,
  r.TagList,
  r.LastEditorDisplayName,
  COALESCE(b.BadgeCount, 0) AS BadgeCount
FROM Ranked r
LEFT JOIN (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
) b ON b.UserId = r.UserId
WHERE rn <= 3
ORDER BY r.Reputation DESC, r.DisplayName ASC
LIMIT 100;