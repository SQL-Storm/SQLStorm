-- {"query": "27027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1559} 

WITH HighReputationUsers AS (
  SELECT
    UserId,
    Reputation,
    DisplayName,
    ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
  FROM
    Users
  WHERE
    Reputation > 10000
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    p.Body,
    EXTRACT(EPOCH FROM (NOW() - t.Count)) AS TimeSinceLastUse,
    p.Id AS PostId,
  p.Title,
    RANK() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS TagRank
  FROM
    Tags t
    JOIN Posts p ON t.ExcerptPostId = p.Id
  WHERE
    t.Count > 500
),
UserPostMetrics AS (
  SELECT
    p.OwnerUserId,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AvgViewCount,
    MAX(p.CreationDate) AS LastPostDate,
    MIN(p.CreationDate) AS FirstPostDate
  FROM
    Posts p
  WHERE
    p.PostTypeId = 1
  GROUP BY
    p.OwnerUserId
),
CommonPostOwners AS (
  SELECT
    u.UserId,
    u.DisplayName,
    upm.PostCount,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY upm.PostCount DESC) AS Rank
  FROM Users u NOT INNER JOIN UserPostMetrics upm ON user.UserId = upm.OwnerUserId
),
ComplicatedPosts AS (

      SELECT
    p.Id AS PostId, p.OwnerUserId, p.PostTypeId, p.ParentId,
    p.AcceptedAnswerId,
            p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Body,
    p.OwnerDisplayName,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    JSON_AGG (
        CASE
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
            THEN jsonb_build_object('UserId', ph.UserId, 'PostHistoryTypeId', ph.PostHistoryTypeId, 'Content', ph.Comment)
            ELSE jsonb_build_object (
              'UserId', ph.UserId, 'PostHistoryTypeId', ph.PostHistoryTypeId
              )
        END) AS PostHistoryArray
  FROM
    Posts p
  LEFT  JOIN
    PostHistory ph ON p.Id = ph.PostId

),
CorrelatedSubQuery AS (
  SELECT
    c.PostId,
    c.Text,
    c.UserId AS CommenterId,
    CreationDate,
    u.DisplayName,
    pn.Name,
  (SELECT COUNT (*)
  FROM Votes v
  WHERE v.PostId = c.PostId
  and v.UserId=c.UserId) AS VoteCounts
  FROM
    Comments c
    JOIN Users u ON c.UserId = u.Id
    JOIN PostHistoryTypes pn on pn.PostHistoryId
  WHERE
    u.Reputation > 5000
    AND c.Text LIKE '%SQL%'
    AND EXTRACT(YEAR FROM pn.CreationDate) = 2023
)

SELECT
  r.DisplayName AS HighRepUser,
  s.TagName AS TopTagName,
  z.Title AS PopularPostTitle,
  COALESCE(z.AnswerCount, 0) AS AnswerCount,
  COALESCE(z.CommentCount, 0) AS CommentCount,
  COALESCE(z.AcceptedAnswerId, 0 ) AS NoOfAcceptAnsers
FROM
  HighReputationUsers r
  JOIN TopTags s ON r.Rank = s.TagRank
  LEFT JOIN Comments c ON c.UserId = r.UserId
  LEFT JOIN Users u ON c.UserId = u.Id
  FULL  OUTER JOIN
  (
    SELECT
    d.UserId,
    d.CreationDate,
    COUNT(d.PostId) AS UserPostCounts,
    a.PostId,
    a.OwnerUserId,
    a.PostTypeId,
    a.ParentId,
    a.AcceptedAnswerId,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.Body,
    a.OwnerDisplayName,
    a.LastEditDate,
    a.LastActivityDate,
    a.Title,
    a.Tags,
    a.AnswerCount,
    a.CommentCount,
    a.FavoriteCount,
    a.ClosedDate,
    a.ContentLicense
    FROM ComplicatedPosts d
    RIGHT JOIN ComplicatedPosts a ON d.OwnerUserId = a.OwnerUserId

    )
  b
   ON
   r.Rank = b.UserId
  LEFT JOIN ComplicatedPosts z ON r.UserId = z.OwnerUserId
WHERE
  EXTRACT(YEAR FROM s.TimeSinceLastUse) < 5
  AND r.Reputation > 15000
GROUP BY
  r.DisplayName,
  s.TagName

UNION
  SELECT
  t.DisplayName,
  i.TagName,
  j.Title,
    COALESCE(j.AnswerCount, 0),
  COALESCE(j.CommentCount, 0),
  COALESCE(j.AcceptedAnswerId, 0 )
FROM
  CommonPostOwners t
  JOIN TopTags i ON t.Rank = i.TagRank
  RIGHT OUTER JOIN ComplicatedPosts j ON j.OwnerUserId = t.UserId
WHERE
  EXTRACT(YEAR FROM i.TimeSinceLastUse) < 5
ORDER BY
  HighRepUser DESC, TopTagName ASC;
 