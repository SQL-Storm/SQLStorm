-- {"query": "5188.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 773} 
WITH
RecentTopQ AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopQuestionAuthors AS (
  SELECT
    rt.PostId,
    rt.Title,
    rt.CreationDate,
    rt.Score,
    rt.ViewCount,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.AccountId,
    rt.Tags,
    rt.rn
  FROM RecentTopQ rt
  JOIN Users u ON u.Id = COALESCE(rt.OwnerUserId, -1)
  WHERE rt.rn <= 50
),
TaggedActivity AS (
  SELECT
    t.TagName,
    vc.PostId,
    vc.CreationDate,
    vc.Score,
    vc.ViewCount,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation
  FROM TopQuestionAuthors qa
  JOIN Posts p ON p.Id = qa.PostId
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t
  JOIN Votes v ON v.PostId = p.Id
  JOIN Users u ON u.Id = p.OwnerUserId
  WHERE t.TagName IS NOT NULL
),
CorrelatedCommentActivity AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.CreationDate AS CommentDate,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.UserId AS CommentUserId,
    du.DisplayName AS CommentUserName
  FROM Comments c
  LEFT JOIN Users du ON du.Id = c.UserId
  WHERE c.CreationDate >= NOW() - INTERVAL '60 days'
),
WindowedPostStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS owner_seq
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
Result AS (
  SELECT
    t.TagName,
    ta.PostId,
    ta.Title,
    ta.CreationDate,
    ta.Score,
    ta.ViewCount,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    ca.CommentDate AS LastCommentDate,
    ca.CommentText AS LastCommentSnippet,
    ws.owner_seq
  FROM TaggedActivity t
  JOIN WindowedPostStats ws ON ws.PostId = t.PostId
  LEFT JOIN CorrelatedCommentActivity ca ON ca.PostId = t.PostId
  LEFT JOIN Users u ON u.Id = t.UserId
  WHERE ws.owner_seq = 1
  GROUP BY
    t.TagName, ta.PostId, ta.Title, ta.CreationDate, ta.Score, ta.ViewCount,
    u.Id, u.DisplayName, u.Reputation, ca.CommentDate, ca.CommentText, ws.owner_seq
)
SELECT
  *
FROM Result
ORDER BY Reputation DESC NULLS LAST, LastCommentDate DESC NULLS LAST
LIMIT 100;