-- {"query": "5030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 912}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.ContentLicense,
    p.Body,
    p.OwnerDisplayName,
    p.LastEditorDisplayName
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
question_activities AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate AS QuestionCreated,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    r.CommentCount,
    ARRAY_AGG(DISTINCT u.DisplayName) FILTER (WHERE vt.VoteTypeId = 2) AS Upvoters,
    ARRAY_AGG(DISTINCT u.DisplayName) FILTER (WHERE vt.VoteTypeId = 3) AS Downvoters
  FROM recent_questions r
  LEFT JOIN Votes vt ON vt.PostId = r.PostId
  LEFT JOIN VoteTypes vtt ON vtt.Id = vt.VoteTypeId
  LEFT JOIN Users u ON vt.UserId = u.Id
  LEFT JOIN Posts p ON p.Id = r.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY r.PostId, r.Title, r.CreationDate, r.LastActivityDate, r.ViewCount, r.Score, r.AnswerCount, r.CommentCount
),
tag_lookup AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
complex_post_summary AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate AS QuestionCreated,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    COALESCE(pv.UpCount, 0) AS UpVotesLast30,
    COALESCE(pv.DownCount, 0) AS DownVotesLast30,
    ARRAY_AGG(DISTINCT tg.TagName) AS TagsList
  FROM recent_questions q
  LEFT JOIN (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownCount
    FROM recent_votes v
    GROUP BY v.PostId
  ) pv ON pv.PostId = q.PostId
  LEFT JOIN LATERAL (
    SELECT trim(both ' ' FROM unnest(string_to_array(q.Tags, ','))) AS tag
  ) t ON true
  LEFT JOIN tag_lookup tg ON tg.TagName = t.tag
  GROUP BY q.PostId, q.Title, q.CreationDate, q.LastActivityDate, q.ViewCount, q.Score, q.AnswerCount, q.CommentCount, pv.UpCount, pv.DownCount
)
SELECT
  cps.PostId,
  cps.Title,
  cps.QuestionCreated,
  cps.LastActivityDate,
  cps.ViewCount,
  cps.Score,
  cps.AnswerCount,
  cps.CommentCount,
  cps.UpVotesLast30,
  cps.DownVotesLast30,
  cps.TagsList,
  u.DisplayName AS Owner,
  u.Reputation AS OwnerReputation,
  u.CreationDate AS OwnerCreationDate
FROM complex_post_summary cps
LEFT JOIN Users u ON u.Id = (
  SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = cps.PostId
)
ORDER BY cps.LastActivityDate DESC
LIMIT 100;