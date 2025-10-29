-- {"query": "5798.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 787} 
WITH TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
RecentWins AS (
  SELECT
    ta.PostId,
    ta.PostTypeId,
    ta.CreationDate,
    ta.Title,
    ta.Tags,
    ta.OwnerUserId,
    ta.ViewCount,
    ta.Score,
    ta.CommentCount,
    ta.AnswerCount,
    ta.LastActivityDate,
    ta.LastEditDate,
    ta.AcceptedAnswerId,
    ta.ParentId,
    ta.OwnerDisplayName,
    u.Reputation,
    u.AccountId,
    u.Location,
    u.LastAccessDate,
    ROW_NUMBER() OVER (
      PARTITION BY ta.OwnerUserId
      ORDER BY ta.LastActivityDate DESC, ta.Score DESC, ta.ViewCount DESC
    ) AS rn_by_user
  FROM TaggedActivity ta
  LEFT JOIN Users u ON ta.OwnerUserId = u.Id
),
Engaged AS (
  SELECT
    rw.PostId,
    rw.PostTypeId,
    rw.CreationDate,
    rw.Title,
    rw.Tags,
    rw.OwnerUserId,
    rw.ViewCount,
    rw.Score,
    rw.CommentCount,
    rw.AnswerCount,
    rw.LastActivityDate,
    rw.LastEditDate,
    rw.AcceptedAnswerId,
    rw.ParentId,
    rw.OwnerDisplayName,
    rw.Reputation,
    rw.AccountId,
    rw.Location,
    rw.LastAccessDate,
    rw.rn_by_user
  FROM RecentWins rw
  WHERE rw.rn_by_user <= 5
),
TopTagActivity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    a.PostId,
    a.Title,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.Location,
    a.Reputation,
    a.AccountId
  FROM (
    SELECT
      TRIM(both '>< ' FROM x.tag) AS TagName,
      COUNT(*) AS Count
    FROM (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
      FROM Posts p
      WHERE p.PostTypeId = 1
    ) x
    GROUP BY TagName
  ) t
  LEFT JOIN Posts a ON a.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  ORDER BY t.Count DESC
  LIMIT 5
)
SELECT
  o.PostId,
  o.PostTypeId,
  o.Title,
  o.CreationDate,
  o.LastActivityDate,
  o.Score,
  o.ViewCount,
  o.CommentCount,
  o.AnswerCount,
  o.OwnerUserId,
  o.OwnerDisplayName,
  o.Reputation,
  o.AccountId,
  o.Location,
  o.LastAccessDate
FROM Engaged o
JOIN PostLinks l ON o.PostId = l.PostId
LEFT JOIN Tags tg ON tg.Id = (
  SELECT Id FROM Tags WHERE TagName = o.Title LIMIT 1
)
LEFT JOIN PostLinks pl ON pl.PostId = o.PostId
ORDER BY o.LastActivityDate DESC, o.Score DESC
LIMIT 100;