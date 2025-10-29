-- {"query": "5968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 883} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Body,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastActivityDate,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.WebsiteUrl,
    u.AboutMe,
    -- window function: rolling sum of views per week for the author
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.CreationDate
                           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS Rolling7DayViews
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
ConnectedStats AS (
  SELECT
    rp.*,
    -- correlated subquery: count of comments for this post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCountForPost,
    -- correlated subquery with potential NULL handling for AcceptedAnswerId
    (SELECT a.Id
     FROM Posts a
     WHERE a.Id = rp.AcceptedAnswerId) AS AcceptedAnswerPostId
  FROM RankedPosts rp
),
Aggregates AS (
  SELECT
    cs.*,
    -- set operator: rough activity score combining views, comments, and favorites
    (cs.ViewCount * 2 + cs.CommentCountForPost * 3 + cs.FavoriteCount) AS ActivityScore
  FROM ConnectedStats cs
),
CrossJoined AS (
  SELECT
    a.*,
    -- string expression: normalized title for search benchmarking
    LOWER(REGEXP_REPLACE(a.Title, '[^a-zA-Z0-9\s]', '', 'g')) AS TitleNormalized,
    -- Tag-based relation: number of tags parsed from Tags field (format: "<tag1><tag2>")
    (CASE WHEN a.Tags IS NULL THEN 0
          ELSE array_length(string_to_array(substring(a.Tags, 2, length(a.Tags)-2), '><'), 1)
     END) AS TagCount
  FROM Aggregates a
)
SELECT
  cj.Id,
  cj.Title,
  cj.Body,
  cj.CreationDate,
  cj.Score,
  cj.ViewCount,
  cj.OwnerUserId,
  cj.DisplayName AS OwnerDisplayName,
  cj.Reputation,
  cj.UserCreationDate,
  cj.LastAccessDate,
  cj.Location,
  cj.Views,
  cj.UpVotes,
  cj.DownVotes,
  cj.ProfileImageUrl,
  cj.EmailHash,
  cj.WebsiteUrl,
  cj.AboutMe,
  cj.LastEditorUserId,
  cj.LastEditorDisplayName,
  cj.LastEditDate,
  cj.LastActivityDate,
  cj.Tags,
  cj.PostTypeId,
  cj.AcceptedAnswerId,
  cj.ParentId,
  cj.CommentCount,
  cj.FavoriteCount,
  cj.ContentLicense,
  cj.Rolling7DayViews,
  cj.CommentCountForPost,
  cj.AcceptedAnswerPostId,
  cj.ActivityScore,
  cj.TitleNormalized,
  cj.TagCount
FROM CrossJoined cj
WHERE
  cj.ActivityScore > 100 -- filter for high-activity posts
  AND cj.PostTypeId = 1 -- focus on questions
  AND EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = cj.Id
      AND v.VoteTypeId IN (2, 12) -- upvotes or deletions to stress test filtering
      AND v.CreationDate >= cj.CreationDate - INTERVAL '30 days'
  )
ORDER BY
  cj.ActivityScore DESC,
  cj.CreationDate DESC
LIMIT 100;