-- {"query": "5498.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 624} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.CommentCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TagScore AS (
  SELECT
    t.TagName AS Tag,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    COUNT(*) AS TotalVotes,
    AVG(p.Score) AS AvgQuestionScore
  FROM Posts p
  JOIN PostLinks pl ON pl.PostId = p.Id
  JOIN Tags t ON t.Id = (SELECT Id FROM Tags WHERE TagName = SPLIT_PART(p.Tags, '><', n.n) LIMIT 1)
  LEFT JOIN Votes v ON v.PostId = p.Id
  CROSS JOIN (VALUES (1),(2),(3),(4)) AS n(n)
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Score DESC NULLS LAST) AS rn
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Reputation > 1000
)
SELECT
  rh.PostId,
  rh.Title AS QuestionTitle,
  rh.CreationDate AS QuestionCreationDate,
  rh.ViewCount,
  rh.Score AS QuestionScore,
  rh.Tags,
  rh.OwnerUserId,
  rh.LastActivityDate,
  rh.FavoriteCount,
  rh.CommentCount,
  ca.TotalVotes AS TagVotes,
  ca.Upvotes AS TagUpvotes,
  ca.Downvotes AS TagDownvotes,
  tu.UserId,
  tu.DisplayName AS AuthorName,
  tu.Reputation AS AuthorReputation,
  tu.LastAccessDate AS AuthorLastAccess
FROM RecentHot rh
LEFT JOIN TagScore ca ON ca.Tag = (SELECT TagName FROM Tags WHERE Id = (SELECT UNNEST(string_to_array(SUBSTRING(rh.Tags, 2, LENGTH(rh.Tags)-2), '><')) LIMIT 1))
LEFT JOIN TopUsers tu ON tu.UserId = rh.OwnerUserId
WHERE rh.rn <= 100
ORDER BY rh.LastActivityDate DESC, rh.Score DESC;