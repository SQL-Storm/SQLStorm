-- {"query": "2336.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1194}
WITH RECURSIVE TagHierarchy(tagId, ParentTagId, Depth) AS (
  SELECT t.Id, CAST(NULL AS INTEGER) AS ParentTagId, 0
  FROM Tags t
  WHERE t.IsRequired = TRUE
  UNION ALL
  SELECT c.Id, p.Id, h.Depth + 1
  FROM Tags c
  JOIN TagHierarchy h ON h.tagId = c.Id - 1
  JOIN Tags p ON p.Id = h.tagId
  WHERE c.IsModeratorOnly = FALSE
),
UserBadgeRank AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY COUNT(b.Id) DESC, u.Reputation DESC) AS Rank
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    COALESCE(a.Score, 0) AS AcceptedAnswerScore,
    COALESCE(cmt.CommentCount, 0) AS CommentCount,
    DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
  FROM Posts p
  LEFT JOIN Posts a ON a.Id = p.AcceptedAnswerId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cmt ON cmt.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
PostHistoryAnalysis AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    pht.Name AS HistoryTypeName,
    COUNT(*) AS ChangesCount,
    MAX(ph.CreationDate) AS LastChangeDate,
    CASE WHEN SUM(CASE WHEN ph.UserId IS NULL THEN 1 ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS HasAnonymousEdit,
    COUNT(DISTINCT ph.UserId) AS DistinctEditors
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  WHERE ph.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
  GROUP BY ph.PostId, ph.PostHistoryTypeId, pht.Name
),
LatestUserActivity AS (
  SELECT
    u.Id,
    u.DisplayName,
    MAX(COALESCE(p.LastActivityDate, u.LastAccessDate)) AS LatestActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    COALESCE(string_agg(DISTINCT COALESCE(t.TagName, 'None'), ', '), 'No Tags') AS TagsInvolved,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT p2.Id AS PostId,
           unnest(string_to_array(SUBSTRING(p2.Tags FROM 2 FOR CHAR_LENGTH(p2.Tags) - 2), '><')) AS TagName
    FROM Posts p2
  ) t ON t.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.LastAccessDate
),
DuplicatesAndLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p1.Title AS PostTitle,
    p2.Title AS RelatedPostTitle
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  JOIN Posts p1 ON p1.Id = pl.PostId
  JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId IN (1,3)
)
SELECT 
  u.DisplayName AS "User",
  u.Reputation,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  psa.Id AS PostId,
  psa.PostTypeId,
  psa.Score,
  psa.ViewCount,
  psa.Title,
  psa.CommentCount,
  psa.AcceptedAnswerScore,
  pha.ChangesCount,
  pha.DistinctEditors,
  la.LatestActivityDate,
  la.TotalUpVotes,
  la.TotalDownVotes,
  la.TagsInvolved,
  dup.LinkTypeName,
  dup.PostTitle,
  dup.RelatedPostTitle,
  CASE 
    WHEN psa.CommentCount > 10 AND psa.Score < 0 THEN 'Controversial'
    WHEN psa.Score > 50 THEN 'Popular'
    ELSE 'Normal'
  END AS PostPopularityCategory
FROM Users u
JOIN UserBadgeRank ub ON ub.UserId = u.Id
LEFT JOIN PostStats psa ON psa.OwnerUserId = u.Id
LEFT JOIN PostHistoryAnalysis pha ON pha.PostId = psa.Id
LEFT JOIN LatestUserActivity la ON la.Id = u.Id
LEFT JOIN DuplicatesAndLinks dup ON dup.PostId = psa.Id
WHERE (psa.ScoreRank <= 100 OR psa.ScoreRank IS NULL)
ORDER BY ub.Rank, psa.Score DESC
LIMIT 100;