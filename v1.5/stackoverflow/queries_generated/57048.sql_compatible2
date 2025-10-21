WITH
  ActiveUsers AS
    (SELECT
      u.Id AS UserId,
      u.Reputation,
      COUNT(p.Id) AS PostCount,
      COUNT(c.Id) AS CommentCount,
      COUNT(v.Id) AS VoteCount
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Votes v ON u.Id = v.UserId
  WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  GROUP BY u.Id, u.Reputation
  HAVING COUNT(p.Id) > 0 OR COUNT(c.Id) > 0 OR COUNT(v.Id) > 0),
PopularTags AS
  (SELECT  t.Id AS TagId,
    t.TagName,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.Id) AS QuestionCount
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
  WHERE p.PostTypeId = 1
  GROUP BY t.Id, t.TagName
  ORDER BY TotalViews DESC
  LIMIT 10),
TagActivity AS
  (SELECT p.Id AS PostId,
    p.CreationDate,
    p.Title,
    p.ViewCount,
    p.AnswerCount,
    u.DisplayName,
    t.TagName
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
  JOIN Users u  ON u.Id = p.OwnerUserId
  JOIN PopularTags pt ON pt.TagId = t.Id
  WHERE p.PostTypeId = 1
  ORDER BY p.ViewCount DESC
  LIMIT 100)
SELECT ta.PostId,
       ta.CreationDate,
       ta.Title,
       ta.ViewCount,
       ta.AnswerCount,
       ta.TagName,
       ta.DisplayName,
       au.UserId,
       au.Reputation,
       au.PostCount,
       au.CommentCount,
       au.VoteCount
FROM TagActivity ta
JOIN ActiveUsers au ON ta.DisplayName = CAST(au.UserId AS VARCHAR);