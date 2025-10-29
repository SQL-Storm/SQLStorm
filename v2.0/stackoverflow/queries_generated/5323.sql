-- {"query": "5323.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1254} 
WITH
RecentActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC, u.Reputation DESC) AS rn
  FROM Users u
  WHERE u.LastAccessDate IS NOT NULL
    AND u.AccountId IS NOT NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
    AND t.IsRequired = 0
),
PostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
    p.ParentId,
    p.ClosedDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= DATEADD(year, -2, GETDATE())
),
VotesSummary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
RecentComments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.Score,
    c.Text,
    c.CreationDate,
    c.UserDisplayName,
    c.ContentLicense
  FROM Comments c
  WHERE c.CreationDate >= DATEADD(year, -2, GETDATE())
),
TagPopularity AS (
  SELECT
    t.TagName,
    tExcerpts.Count AS TagCountExcerpts
  FROM TopTags tExcerpts
)
SELECT
  -- Per-user performance snapshot with advanced predicates
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  u.AccountId,
  u.LastAccessDate,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  COALESCE(u.Views, 0) AS Views,
  COALESCE(u.UpVotes, 0) AS UpVotes,
  COALESCE(u.DownVotes, 0) AS DownVotes,
  u.ProfileImageUrl,
  u.EmailHash,
  -- Aggregated post activity by user
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  SUM(p.ViewCount) AS ViewCountTotal,
  SUM(vs.UpVotes) AS TotalUpVotesOnPosts,
  SUM(vs.DownVotes) AS TotalDownVotesOnPosts,
  SUM(vs.BountyStarts) AS TotalBountyStarts,
  SUM(vs.BountyCloses) AS TotalBountyCloses,
  -- Latest activity details
  MAX(p.LastActivityDate) AS LastActivityDate,
  MAX(p.LastEditDate) AS LastEditDate,
  -- Tags associated with the user's questions (via posts)
  STRING_AGG(t.TagName, ',') AS FavoriteTags, -- requires compatible DB (PostgreSQL/SQL Server 2017+)
  -- Complex computed string expression
  CONCAT(
    'U', CAST(u.Id AS varchar(20)), ' | ',
    'Rep:', CAST(u.Reputation AS varchar(20)), ' | ',
    'Posts:', CAST(
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) + SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END
      ) AS varchar(20)
    )
  ) AS MetaSummary
FROM RecentActiveUsers u
LEFT JOIN PostActivity p ON p.OwnerUserId = u.Id
LEFT JOIN VotesSummary vs ON vs.PostId = p.Id
LEFT JOIN PostLinksAgg pla ON pla.PostId = p.Id
LEFT JOIN Posts tPost ON tPost.Id = p.Id
LEFT JOIN TopTags tt ON 1=1
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.AccountId,
  u.LastAccessDate,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.ProfileImageUrl,
  u.EmailHash
HAVING
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
  OR SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 0
ORDER BY
  LastActivityDate DESC,
  Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;