-- {"query": "5444.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865} 
WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId AS AuthorId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    -- Window function to rank questions by engagement (score * 2 + view count + answer count)
    ROW_NUMBER() OVER (
      ORDER BY (p.Score * 2) + p.ViewCount + COALESCE(p.AnswerCount, 0) DESC,
               p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
Engagement AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate,
    tq.AuthorId,
    tq.Score,
    tq.ViewCount,
    tq.Tags,
    tq.LastActivityDate,
    tq.AnswerCount,
    tq.CommentCount,
    tq.FavoriteCount,
    tq.Body,
    tq.LastEditorUserId,
    tq.LastEditDate,
    tq.ContentLicense,
    -- Correlated subquery: number of comments by non-null authors within 7 days of creation
    (
      SELECT COUNT(*) FROM Comments c
      WHERE c.PostId = tq.PostId
        AND c.CreationDate >= tq.CreationDate
        AND c.CreationDate < tq.CreationDate + INTERVAL '7 days'
    ) AS NewCommentsWeek
  FROM TopQuestions tq
  WHERE rn <= 100 -- top 100 by engagement
),
TagStats AS (
  SELECT
    e.PostId,
    e.Title,
    e.Body,
    t.TagName,
    t.Count AS TagPopularCount,
    -- Compute a synthetic score per tag based on tag popularity and post score
    (e.Score * 0.6) + (t.Count * 0.4) AS TagBoost
  FROM Engagement e
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(e.Tags, 2, length(e.Tags)-2), '><')) AS TagName
  ) AS tag_split
  LEFT JOIN Tags t ON t.TagName = tag_split.TagName
  WHERE t.Count IS NOT NULL
),
Filtered AS (
  SELECT
    ts.PostId,
    ts.Title,
    ts.Body,
    ts.TagName,
    ts.TagPopularCount,
    ts.TagBoost
  FROM TagStats ts
  ORDER BY ts.TagBoost DESC
  LIMIT 50
),
Attendance AS (
  SELECT
    f.PostId,
    f.Title,
    f.TagName,
    u2.DisplayName AS LastEditorName,
    u2.Reputation AS EditorReputation,
    COALESCE(v2.BountyAmount, 0) AS Bounty
  FROM Filtered f
  LEFT JOIN Users u2 ON f.PostId = f.PostId
  LEFT JOIN Votes v2 ON v2.PostId = f.PostId
  WHERE f.TagName IS NOT NULL
)
SELECT
  a.PostId,
  a.Title,
  a.TagName,
  a.Body,
  a.LastEditorName,
  a.EditorReputation,
  a.Bounty,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId IN (2,7)) AS UpOrReopenVotes,
  (SELECT STRING_AGG(CONCAT('User:', u.DisplayName, '(', u.Reputation, ')'), ', ')
   FROM Votes v JOIN Users u ON v.UserId = u.Id
   WHERE v.PostId = a.PostId AND v.VoteTypeId = 2) AS Upvoters,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = a.PostId) AS LastVoteDate
FROM Attendance a
ORDER BY a.TagBoost DESC, a.LastEditorName
LIMIT 100;