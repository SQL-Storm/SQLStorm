WITH
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastActivityForUser
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
TopVotes AS (
  SELECT
    v.UserId,
    v.PostId,
    v.VoteTypeId,
    v.CreationDate,
    p.PostTypeId,
    p.Title,
    p.Tags,
    (CASE v.VoteTypeId
      WHEN 2 THEN 3
      WHEN 10 THEN 5
      WHEN 11 THEN 4
      WHEN 14 THEN 6
      WHEN 16 THEN 7
      ELSE 1
    END) *
    (CASE p.PostTypeId
      WHEN 1 THEN 2
      WHEN 2 THEN 1
      ELSE 0
    END) AS Weight
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  WHERE v.CreationDate >= DATE '2024-10-01' - INTERVAL '2 year'
    AND v.VoteTypeId IN (2, 10, 11, 14, 16)
),
RollingActivity AS (
  SELECT
    tv.UserId,
    tv.PostId,
    tv.VoteTypeId,
    tv.CreationDate,
    tv.Weight,
    SUM(tv.Weight) OVER (
      PARTITION BY tv.UserId
      ORDER BY tv.CreationDate
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS SevenDayWeight
  FROM TopVotes tv
),
HotPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId IN (1,3)) AS RelatedLinks,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
  FROM Posts p
  WHERE p.LastActivityDate >= DATE '2024-10-01' - INTERVAL '6 month'
),
PostRanking AS (
  SELECT
    hp.PostId,
    hp.Title,
    hp.Tags,
    hp.ViewCount,
    hp.Score,
    hp.RelatedLinks,
    hp.IsCommunityOwned,
    ROW_NUMBER() OVER (
      ORDER BY
        hp.ViewCount * 0.4 +
        hp.Score * 0.6 +
        hp.RelatedLinks * 0.2 +
        hp.IsCommunityOwned * 5
    ) AS Ranking,
    hp.LastActivityDate
  FROM HotPosts hp
  WHERE hp.LastActivityDate >= DATE '2024-10-01' - INTERVAL '1 month'
),
BenchmarkQuery AS (
  SELECT
    us.UserId,
    us.UserName,
    us.Reputation,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    ro.SevenDayWeight,
    pr.PostId,
    pr.Title AS PostTitle,
    pr.Tags AS PostTags,
    pr.ViewCount AS PostViews,
    pr.Score AS PostScore,
    pr.RelatedLinks,
    pr.IsCommunityOwned,
    ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY pr.Ranking) AS UserPostRank
  FROM UserStats us
  LEFT JOIN RollingActivity ro ON ro.UserId = us.UserId
  LEFT JOIN (
    SELECT PostId, Title, Tags, ViewCount, Score, RelatedLinks, IsCommunityOwned, Ranking
    FROM PostRanking
  ) pr ON pr.PostId = ro.PostId
)
SELECT
  UserId,
  UserName,
  Reputation,
  PostCount,
  QuestionCount,
  AnswerCount,
  SevenDayWeight,
  PostId,
  PostTitle,
  PostTags,
  PostViews,
  PostScore,
  RelatedLinks,
  IsCommunityOwned,
  UserPostRank
FROM BenchmarkQuery
WHERE UserPostRank <= 5
ORDER BY UserName, UserPostRank;