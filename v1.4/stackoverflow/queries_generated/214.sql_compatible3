WITH
per_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(MAX(p.LastActivityDate), u.CreationDate) AS LastActivityDate,
    COUNT(p.Id) AS TotalPosts,
    COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
votes_agg AS (
  SELECT
    p.OwnerUserId AS UserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes
  FROM Votes v
  JOIN Posts p ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
),
tag_list AS (
  SELECT
    p.OwnerUserId AS UserId,
    LOWER(TRIM(TagName)) AS TagName
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT TRIM(value) AS TagName
    FROM UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS value
  ) AS TagNameAlias
  WHERE p.Tags IS NOT NULL
),
tag_counts AS (
  SELECT UserId, COUNT(DISTINCT TagName) AS UniqueTagCount
  FROM tag_list
  GROUP BY UserId
),
top_posts AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Score,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.TotalPosts,
  u.TotalViews,
  u.TotalScore,
  u.QuestionCount,
  COALESCE(MAX(v.UpVotes), 0) AS UpVotes,
  COALESCE(MAX(v.DownVotes), 0) AS DownVotes,
  COALESCE(MAX(v.AcceptedVotes), 0) AS AcceptedVotes,
  COALESCE(MAX(tc.UniqueTagCount), 0) AS UniqueTagCount,
  COALESCE(u.LastActivityDate, NULL) AS LastActivityDate,
  COALESCE(MAX(CASE WHEN tp.rn = 1 THEN tp.Score END), 0) AS TopPostScore
FROM per_user u
LEFT JOIN votes_agg v ON v.UserId = u.UserId
LEFT JOIN tag_counts tc ON tc.UserId = u.UserId
LEFT JOIN top_posts tp ON tp.UserId = u.UserId
GROUP BY
  u.UserId,
  u.DisplayName,
  u.Reputation,
  u.TotalPosts,
  u.TotalViews,
  u.TotalScore,
  u.QuestionCount,
  u.LastActivityDate
ORDER BY (COALESCE(MAX(v.UpVotes), 0) - COALESCE(MAX(v.DownVotes), 0)) DESC,
         u.Reputation DESC,
         u.TotalScore DESC
LIMIT 200;