WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.AnswerCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Title, 
    p.Tags,
    u.Reputation,
    u.AccountId,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(b.Name, '') AS Badges,
    COALESCE(b.Class, 0) AS BadgeClass,
    CASE WHEN b.TagBased IS NULL THEN 0 ELSE CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END END AS TagBasedBadge,
    CASE 
      WHEN p.PostTypeId = 1 THEN (
        SELECT COUNT(*) 
        FROM Votes 
        WHERE PostId = p.Id AND VoteTypeId = 1
      )
      ELSE 0
    END AS AcceptedAnswers,
    COALESCE(pl.LinkTypeId, 0) AS LinkTypeId,
    COALESCE(pl.RelatedPostId, 0) AS RelatedPostId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT Id AS UserId, SUM(COALESCE(UpVotes,0)) AS UpVotes, SUM(COALESCE(DownVotes,0)) AS DownVotes 
    FROM Users
    GROUP BY Id
  ) v ON u.Id = v.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
),
agg AS (
  SELECT
    Id,
    PostTypeId,
    AnswerCount,
    CreationDate,
    OwnerUserId,
    Title,
    Tags,
    Reputation,
    AccountId,
    UpVotes,
    DownVotes,
    STRING_AGG(Badges, ',') AS Badges,
    MAX(BadgeClass) AS BadgeClass,
    MAX(TagBasedBadge) AS TagBasedBadge,
    AcceptedAnswers,
    STRING_AGG(CAST(LinkTypeId AS VARCHAR), ',') AS LinkTypes,
    STRING_AGG(CAST(RelatedPostId AS VARCHAR), ',') AS RelatedPostIds
  FROM cte
  GROUP BY 
    Id, 
    PostTypeId,
    AnswerCount,
    CreationDate,
    OwnerUserId,
    Title,
    Tags,
    Reputation,
    AccountId,
    UpVotes,
    DownVotes,
    AcceptedAnswers
)
SELECT
  Id,
  PostTypeId,
  AnswerCount,
  CreationDate,
  OwnerUserId,
  Title,
  Tags,
  Reputation,
  AccountId,
  UpVotes,
  DownVotes,
  Badges,
  BadgeClass,
  TagBasedBadge,
  AcceptedAnswers,
  LinkTypes,
  RelatedPostIds,
  DENSE_RANK() OVER (PARTITION BY OwnerUserId ORDER BY UpVotes DESC) AS UpVotesRank,
  DENSE_RANK() OVER (PARTITION BY OwnerUserId ORDER BY DownVotes DESC) AS DownVotesRank,
  DENSE_RANK() OVER (PARTITION BY OwnerUserId ORDER BY Reputation DESC) AS ReputationRank,
  CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - CAST(CreationDate AS TIMESTAMP))) / 86400 AS INTEGER) AS DaysSinceCreation
FROM agg;