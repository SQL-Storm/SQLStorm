-- {"query": "885.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1353} 

WITH
-- Recent active users with at least 5 posts in last 6 months
ActiveUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
         COUNT(p.Id) AS RecentPostCount,
         AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= NOW() - INTERVAL '6 months'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(p.Id) >= 5
),

-- Top 3 badges per user by date
UserTopBadges AS (
  SELECT b.UserId, b.Name, b.Class, b.Date,
         ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC, b.Class) AS rn
  FROM Badges b
  WHERE b.UserId IN (SELECT Id FROM ActiveUsers)
),

-- Posts with complex tag parsing and score weighted by age
PostTagScores AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.PostTypeId,
         p.Score,
         p.CreationDate,
         p.Title,
         p.Tags,
         unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS Tag,
         EXTRACT(EPOCH FROM (NOW() - p.CreationDate))/86400.0 AS AgeDays,
         CASE
           WHEN p.Score IS NULL THEN 0
           ELSE p.Score / (1 + EXTRACT(EPOCH FROM (NOW() - p.CreationDate))/86400.0)
         END AS WeightedScore
  FROM Posts p
  WHERE p.Tags IS NOT NULL AND p.Tags LIKE '<%>%'
),

-- Average weighted score per tag for posts by active users
TagAvgScores AS (
  SELECT pts.Tag,
         AVG(pts.WeightedScore) AS AvgWeightedScore,
         COUNT(*) AS PostCount
  FROM PostTagScores pts
  JOIN ActiveUsers au ON pts.OwnerUserId = au.Id
  GROUP BY pts.Tag
  HAVING COUNT(*) > 10
),

-- Latest comment per post with complex NULL logic and substring extraction
LatestComments AS (
  SELECT DISTINCT ON (c.PostId)
         c.PostId,
         c.Id AS CommentId,
         c.UserId,
         c.UserDisplayName,
         c.CreationDate AS CommentDate,
         LEFT(c.Text, 50) || CASE WHEN length(c.Text) > 50 THEN '...' ELSE '' END AS ShortText
  FROM Comments c
  WHERE c.Text IS NOT NULL
  ORDER BY c.PostId, c.CreationDate DESC
),

-- Correlated subquery: count of distinct users commenting on each post
PostCommentUserCount AS (
  SELECT p.Id AS PostId,
         (SELECT COUNT(DISTINCT c.UserId) FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS DistinctCommenters
  FROM Posts p
  WHERE p.PostTypeId = 1
),

-- Posts with left join on accepted answers and their owner reputations
PostsWithAcceptedAnswers AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.Score AS QuestionScore,
         aa.Id AS AcceptedAnswerId,
         aa.Score AS AcceptedAnswerScore,
         u2.Id AS AcceptedAnswerOwnerId,
         u2.DisplayName AS AcceptedAnswerOwner,
         u2.Reputation AS AcceptedAnswerOwnerRep
  FROM Posts p
  LEFT JOIN Posts aa ON aa.Id = p.AcceptedAnswerId
  LEFT JOIN Users u2 ON u2.Id = aa.OwnerUserId
  WHERE p.PostTypeId = 1
),

-- Combine all info for active users and their posts with badges and accepted answers
UserPostSummary AS (
  SELECT au.Id AS UserId, au.DisplayName AS UserName, au.Reputation AS UserRep, au.RecentPostCount,
         utb.Name AS BadgeName, utb.Class AS BadgeClass, utb.Date AS BadgeDate,
         pwa.QuestionId, pwa.Title, pwa.CreationDate AS QuestionDate, pwa.QuestionScore,
         pwa.AcceptedAnswerId, pwa.AcceptedAnswerScore, pwa.AcceptedAnswerOwner, pwa.AcceptedAnswerOwnerRep,
         pcu.DistinctCommenters,
         lc.CommentId, lc.UserDisplayName AS CommenterName, lc.CommentDate, lc.ShortText AS CommentSnippet
  FROM ActiveUsers au
  LEFT JOIN UserTopBadges utb ON utb.UserId = au.Id AND utb.rn <= 3
  LEFT JOIN PostsWithAcceptedAnswers pwa ON pwa.QuestionId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = au.Id AND p.PostTypeId = 1
      )
  LEFT JOIN PostCommentUserCount pcu ON pcu.PostId = pwa.QuestionId
  LEFT JOIN LatestComments lc ON lc.PostId = pwa.QuestionId
),

-- Final aggregation to rank tags by average weighted score and join with user post summary
RankedTags AS (
  SELECT Tag,
         AvgWeightedScore,
         PostCount,
         RANK() OVER (ORDER BY AvgWeightedScore DESC) AS TagRank
  FROM TagAvgScores
)

SELECT DISTINCT
       r.TagRank,
       r.Tag,
       ROUND(r.AvgWeightedScore::numeric, 3) AS AvgWeightedScore,
       r.PostCount,
       ups.UserName,
       ups.UserRep,
       ups.RecentPostCount,
       ups.BadgeName,
       CASE ups.BadgeClass
         WHEN 1 THEN 'Gold'
         WHEN 2 THEN 'Silver'
         WHEN 3 THEN 'Bronze'
         ELSE 'Unknown'
       END AS BadgeClass,
       ups.BadgeDate,
       ups.QuestionDate,
       ups.Title AS QuestionTitle,
       ups.QuestionScore,
       ups.AcceptedAnswerScore,
       ups.AcceptedAnswerOwner,
       ups.AcceptedAnswerOwnerRep,
       ups.DistinctCommenters,
       ups.CommenterName,
       ups.CommentDate,
       ups.CommentSnippet
FROM RankedTags r
LEFT JOIN UserPostSummary ups ON ups.QuestionTitle IS NOT NULL
WHERE r.TagRank <= 10
ORDER BY r.TagRank, ups.UserRep DESC NULLS LAST, ups.QuestionScore DESC NULLS LAST
LIMIT 100;
