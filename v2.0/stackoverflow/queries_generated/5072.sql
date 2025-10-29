-- {"query": "5072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 823} 
WITH
-- sample derived tables to enrich data
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
),
TopTags AS (
  SELECT t.TagName,
         COUNT(*) AS TagCount,
         AVG(p.Score) AS AvgScore
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN UNNEST(string_to_array(tg.TagName, '>')) AS t(TagName) ON true
  GROUP BY t.TagName
  ORDER BY TagCount DESC
  LIMIT 50
),
QuestionActivity AS (
  SELECT q.PostId,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.Tags,
         COALESCE(vs.TotalUp,0) AS TotalUp,
         COALESCE(vs.TotalDown,0) AS TotalDown,
         COALESCE(vs.Accepted,0) AS Accepted,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount
  FROM RecentQuestions q
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDown,
           SUM(CASE WHEN vt.Id = 1 THEN 1 ELSE 0 END) AS Accepted
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY PostId
  ) vs ON vs.PostId = q.PostId
),
-- cross join with a windowed view on users for NULL/formatting tests
UserScore AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate DESC) AS rn
  FROM Users u
),
 -- combine posts with links to related posts to exercise outer joins and set operations
PostLinksAgg AS (
  SELECT pl.PostId,
         pl.RelatedPostId,
         lt.Name AS LinkType,
         p.Title AS RelatedTitle
  FROM PostLinks pl
  LEFT JOIN Posts p ON p.Id = pl.RelatedPostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
)
SELECT
  q.PostId,
  q.Title,
  q.CreationDate,
  q.Score,
  q.ViewCount,
  q.Tags,
  q.TotalUp,
  q.TotalDown,
  q.Accepted,
  q.CommentCount,
  STRING_AGG(DISTINCT tl.RelatedPostId::text, ',') AS RelatedPostIds,
  STRING_AGG(DISTINCT tl.LinkType, ',') AS LinkTypes,
  STRING_AGG(DISTINCT u.DisplayName, ',') AS TopCommenters
FROM QuestionActivity q
LEFT JOIN PostLinksAgg tl ON tl.PostId = q.PostId
LEFT JOIN Comments c ON c.PostId = q.PostId
LEFT JOIN Users l ON l.Id = c.UserId
LEFT JOIN (
  SELECT DISTINCT UserDisplayName
  FROM Comments
  WHERE UserDisplayName IS NOT NULL
) t ON t.UserDisplayName IS NOT NULL
GROUP BY
  q.PostId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.TotalUp, q.TotalDown, q.Accepted, q.CommentCount
ORDER BY q.CreationDate DESC
LIMIT 100;