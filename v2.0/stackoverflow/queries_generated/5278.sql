-- {"query": "5278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1010} 
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.PostTypeId,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) OVER () AS LastUpvoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId,
    p.Tags, p.LastActivityDate, p.AcceptedAnswerId, p.PostTypeId, p.CommentCount
),
author_scores AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    uf.TotalPostViews,
    uf.AvgPostScore
  FROM Users u
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(ViewCount) AS TotalPostViews,
      AVG(Score) AS AvgPostScore
    FROM Posts
    GROUP BY OwnerUserId
  ) uf ON uf.OwnerUserId = u.Id
  WHERE u.Id IN (
    SELECT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL
  )
),
popular_tags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS TagScore,
    COUNT(p.Id) AS PostCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId OR p.Id = tg.WikiPostId
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t ON TRUE
  WHERE tg.IsModeratorOnly = 0
  GROUP BY t.TagName
  ORDER BY TagScore DESC
  LIMIT 20
)
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  rp.CreationDate AS PostCreationDate,
  rp.ViewCount,
  rp.Score AS PostScore,
  rp.LastActivityDate,
  rp.OwnerUserId,
  au.DisplayName AS AuthorName,
  au.Reputation AS AuthorReputation,
  COALESCE(rp.UpVotes, 0) AS UpVotes,
  COALESCE(rp.DownVotes, 0) AS DownVotes,
  a.DisplayName AS LastEditorName,
  m.TagName AS MostUsedTag,
  pt.Name AS PostType,
  (CASE
     WHEN rp.CommentCount IS NULL THEN 0
     ELSE rp.CommentCount
   END) AS CommentCount,
  (CASE
     WHEN rp.AcceptedAnswerId IS NOT NULL THEN true
     ELSE false
   END) AS HasAcceptedAnswer,
  (CASE
     WHEN rp.PostTypeId = 1 THEN 'Question'
     WHEN rp.PostTypeId = 2 THEN 'Answer'
     ELSE 'Other'
   END) AS PostKind,
  (SELECT STRING_AGG(DISTINCT lt.Name, ',')
     FROM PostLinks pl
     JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
     WHERE pl.PostId = rp.PostId) AS LinkTypesUsed,
  COALESCE((SELECT MAX(CreationDate) FROM Votes v2 WHERE v2.PostId = rp.PostId AND v2.VoteTypeId = 2), NULL) AS LastUpvoteDate
FROM recent_activity rp
LEFT JOIN Users au ON au.Id = rp.OwnerUserId
LEFT JOIN Users a ON a.Id = rp.LastEditorUserId
LEFT JOIN (
  SELECT PostId, MAX(TagName) AS TagName
  FROM (
    SELECT p.Id AS PostId, unnest(string_to_array(p.Tags, '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
  ) s
  GROUP BY PostId
) m ON m.PostId = rp.PostId
LEFT JOIN PostTypes pt ON pt.Id = rp.PostTypeId
WHERE rp.ViewCount > 0
ORDER BY rp.LastActivityDate DESC, rp.Score DESC
OFFSET 0 ROWS
FETCH FIRST 100 ROWS ONLY;