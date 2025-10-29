-- {"query": "5105.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 966} 
WITH top_users AS (
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
    u.EmailHash,
    u.AccountId,
    COUNT(DISTINCT p.Id) AS PostCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.EmailHash, u.AccountId
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM
    Posts p
  WHERE
    p.LastActivityDate > DATEADD(day, -30, GETDATE())
),
edge_cases AS (
  SELECT
    v.UserId,
    v.PostId,
    vt.Name AS VoteType,
    v.CreationDate AS VoteDate,
    v.BountyAmount
  FROM
    Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE
    v.CreationDate >= DATEADD(day, -7, GETDATE())
),
tag_cooccurrence AS (
  SELECT
    t1.TagName AS TagA,
    t2.TagName AS TagB,
    COUNT(*) AS Cooccurrence
  FROM
    Tags ta
    JOIN Tags tb ON ta.Id <> tb.Id
  WHERE
    ta.TagName IS NOT NULL AND tb.TagName IS NOT NULL
  GROUP BY
    t1.TagName, t2.TagName
  HAVING
    COUNT(*) > 5
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.PostCount,
  tu.AvgQuestionScore,
  tu.AvgAnswerScore,
  ra.PostId AS TopPostId,
  ra.PostTypeId AS TopPostType,
  ra.Title AS TopPostTitle,
  ra.LastActivityDate AS TopPostDate,
  ra.ViewCount AS TopPostViews,
  ec.VoteDate AS RecentVoteDate,
  ec.VoteType,
  ec.BountyAmount,
  ce.TagA,
  ce.TagB,
  ce.Cooccurrence AS TagCooccurrence,
  ARRAY_AGG(DISTINCT CASE WHEN p2.Id IS NOT NULL THEN p2.Id END) FILTER (WHERE p2.Id IS NOT NULL) AS RelatedPostIds
FROM
  top_users tu
  LEFT JOIN recent_activity ra ON ra.OwnerUserId = tu.UserId AND ra.rn = 1
  LEFT JOIN edge_cases ec ON ec.UserId = tu.UserId
  LEFT JOIN (
    SELECT
      p1.OwnerUserId,
      p2.Id
    FROM
      Posts p1
      JOIN Posts p2 ON p2.ParentId = p1.Id
    WHERE
      p1.OwnerUserId = tu.UserId
  ) p2 ON p2.OwnerUserId = tu.UserId
  LEFT JOIN (
    SELECT
      t1.TagName AS TagA,
      t2.TagName AS TagB,
      COUNT(*) AS Cooccurrence
    FROM
      Tags t1
      JOIN Tags t2 ON t1.Id <> t2.Id
    GROUP BY t1.TagName, t2.TagName
  ) ce ON TRUE
GROUP BY
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.PostCount,
  tu.AvgQuestionScore,
  tu.AvgAnswerScore,
  ra.PostId,
  ra.PostTypeId,
  ra.Title,
  ra.LastActivityDate,
  ra.ViewCount,
  ec.VoteDate,
  ec.VoteType,
  ec.BountyAmount,
  ce.TagA,
  ce.TagB,
  ce.Cooccurrence;