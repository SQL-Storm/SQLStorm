-- {"query": "1295.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1228} 

WITH RecentHighScorePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions only
    AND p.Score >= (SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1)
    AND p.ClosedDate IS NULL
),
UserTotals AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS NumHighlySkoredQuestions,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(SUM(c.Score), 0) AS CommentScores,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    MAX(p.CreationDate) AS LastQuestionDate,
    AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
    STRING_AGG(DISTINCT COALESCE(t.TagName, 'Unknown'), ', ') FILTER (WHERE t.TagName IS NOT NULL) AS DistinctTags,
    EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 1 LIMIT 1) AS HasAcceptedVote
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT DISTINCT pt.Id, pt.TagName
    FROM Posts p2
    CROSS JOIN LATERAL unnest(string_to_array(trim(both '<>' FROM COALESCE(p2.Tags, '')), '><')) pt(TagName)
    WHERE p2.PostTypeId = 1
  ) t ON POSITION('<'||t.TagName||'>' IN COALESCE(p.Tags, '')) > 0
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 0
),
PostWithLinks AS (
  SELECT 
    p.Id,
    p.Title,
    p.OwnerUserId,
    l.RelatedPostId,
    lt.Name AS LinkTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY l.CreationDate DESC) AS LinkRank
  FROM Posts p
  LEFT JOIN PostLinks l ON l.PostId = p.Id
  LEFT JOIN LinkTypes lt ON lt.Id = l.LinkTypeId
  WHERE p.PostTypeId = 1
)
SELECT
  u.UserId,
  u.DisplayName,
  u.NumHighlySkoredQuestions,
  u.TotalScore,
  u.CommentScores,
  u.GoldBadges,
  u.SilverBadges,
  u.BronzeBadges,
  u.LastQuestionDate,
  u.AvgPostScore,
  u.DistinctTags,
  CASE WHEN u.HasAcceptedVote THEN 'Yes' ELSE 'No' END AS HasAcceptedVote,
  p.Id AS PostId,
  p.Title AS PostTitle,
  p.LinkTypeName,
  p.RelatedPostId,
  
  -- Subquery correlated to count distinct users who commented on same posts of this user
  (SELECT COUNT(DISTINCT c2.UserId)
   FROM Comments c2
   JOIN Posts p2 ON p2.Id = c2.PostId
   WHERE p2.OwnerUserId = u.UserId
     AND c2.UserId IS NOT NULL
     AND c2.UserId <> u.UserId) AS DistinctCommentersOnUserPosts,
  
  -- Complex expression with NULL handling and string functions
  CASE 
    WHEN p.Title IS NULL THEN 'NO_TITLE'
    ELSE SUBSTRING(REPLACE(REGEXP_REPLACE(p.Title, '[^a-zA-Z0-9 ]', '', 'g'), '  ', ' '), 1, 50)
  END AS CleanTitleSnippet,
  
  -- Window function showing cumulative sum of Score over time per user
  SUM(u.TotalScore) OVER (PARTITION BY u.UserId ORDER BY u.LastQuestionDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningUserScore,
  
  -- Set operator: list of tags of posts owned by user minus tags in RecentHighScorePosts
  array_to_string(
    ARRAY(
      SELECT DISTINCT trim(TAGS_TAG) FROM unnest(string_to_array(coalesce(p.Tags, ''), '><')) AS TAGS_TAG
      EXCEPT
      SELECT DISTINCT trim(TAGS_TAG)
      FROM RecentHighScorePosts rhp, unnest(string_to_array(coalesce(rhp.Tags, ''), '><')) AS TAGS_TAG
      WHERE rhp.OwnerUserId = u.UserId
    ),
  ', ') AS MissingTagsFromRecentHighScores,

  -- Outer join logic: last editor user’s display name or the original owner display name
  COALESCE(
    (SELECT DisplayName FROM Users WHERE Id = (SELECT LastEditorUserId FROM Posts WHERE Id = p.Id) LIMIT 1),
    u.DisplayName
  ) AS LastEditorOrOwner

FROM UserTotals u
LEFT JOIN PostWithLinks p ON p.OwnerUserId = u.UserId
WHERE p.LinkRank = 1 OR p.LinkRank IS NULL
ORDER BY u.TotalScore DESC NULLS LAST, u.NumHighlySkoredQuestions DESC
LIMIT 50;
