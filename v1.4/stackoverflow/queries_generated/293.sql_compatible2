WITH
OpenPosts AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.AcceptedAnswerId
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
PostTypesCTE AS (
  SELECT Id, Name FROM PostTypes
),
Owner AS (
  SELECT u.Id AS UserId, COALESCE(u.DisplayName, CAST(u.AccountId AS TEXT), 'Unknown') AS OwnerName, u.Reputation
  FROM Users u
),
CommentsAgg AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
VotesAgg AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
),
LinkTypesAgg AS (
  SELECT pl.PostId, STRING_AGG(lt.Name, ',') AS LinkTypes
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
TagNamesAgg AS (
  SELECT t.ExcerptPostId AS PostId, STRING_AGG(t.TagName, ',') AS TagsList
  FROM Tags t
  GROUP BY t.ExcerptPostId
),
LatestHist AS (
  SELECT ph.PostId, MAX(ph.CreationDate) AS LastChangeDate, MAX(ph.Id) AS LastHistoryId
  FROM PostHistory ph
  GROUP BY ph.PostId
)
SELECT
  p.Id AS PostId,
  (SELECT pt.Name FROM PostTypesCTE pt WHERE pt.Id = p.PostTypeId) AS PostType,
  COALESCE(o.OwnerName, CAST(p.OwnerUserId AS TEXT), 'Unknown') AS OwnerName,
  p.Title,
  p.Tags,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  COALESCE(cc.CommentCount, 0) AS CommentCount,
  COALESCE(v.UpVotes, 0) AS UpVotes,
  COALESCE(v.DownVotes, 0) AS DownVotes,
  (COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) AS NetVoteDelta,
  COALESCE(l.LinkTypes, '') AS LinkTypes,
  COALESCE(tg.TagsList, NULL) AS TagsList,
  o.Reputation,
  lh.LastChangeDate,
  lh.LastHistoryId,
  ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS ActivityRank,
  CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
  LOWER(REPLACE(p.Title, ' ', '_')) AS TitleSlug,
  (
    SELECT COUNT(*) FROM Posts pp
    WHERE pp.OwnerUserId = p.OwnerUserId
      AND pp.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
  ) AS PostsLast30Days
FROM OpenPosts p
LEFT JOIN Owner o ON o.UserId = p.OwnerUserId
LEFT JOIN CommentsAgg cc ON p.Id = cc.PostId
LEFT JOIN VotesAgg v ON p.Id = v.PostId
LEFT JOIN LinkTypesAgg l ON p.Id = l.PostId
LEFT JOIN TagNamesAgg tg ON p.Id = tg.PostId
LEFT JOIN LatestHist lh ON p.Id = lh.PostId
ORDER BY NetVoteDelta DESC NULLS LAST
LIMIT 200;