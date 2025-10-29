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
  WHERE p.PostTypeId = 1
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
  CROSS JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) numbers
  JOIN Tags t ON t.TagName = (
    SELECT tag FROM (
      SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), '><')) AS tag, row_number() OVER () AS rn
    ) sub WHERE sub.rn = numbers.n
  )
  LEFT JOIN Votes v ON v.PostId = p.Id
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
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id ASC) AS rn
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
LEFT JOIN TagScore ca ON ca.Tag = (
  SELECT tag FROM (
    SELECT UNNEST(string_to_array(SUBSTRING(rh.Tags FROM 2 FOR (CHAR_LENGTH(rh.Tags)-2)), '><')) AS tag, row_number() OVER () AS rn
  ) sub WHERE sub.rn = 1
)
LEFT JOIN TopUsers tu ON tu.UserId = rh.OwnerUserId
WHERE rh.rn <= 100
GROUP BY
  rh.PostId,
  rh.Title,
  rh.CreationDate,
  rh.ViewCount,
  rh.Score,
  rh.Tags,
  rh.OwnerUserId,
  rh.LastActivityDate,
  rh.FavoriteCount,
  rh.CommentCount,
  ca.TotalVotes,
  ca.Upvotes,
  ca.Downvotes,
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.LastAccessDate,
  rh.rn
ORDER BY rh.LastActivityDate DESC, rh.Score DESC;