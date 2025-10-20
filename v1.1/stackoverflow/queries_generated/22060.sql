-- {"query": "22060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 823} 
WITH UserStats AS (
    SELECT u.Id, u.Reputation, u.CreationDate,
           COUNT(DISTINCT p.Id) AS NumPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumQuestions,
           AVG(p.Score) AS AvgPostScore,
           SUM(p.ViewCount) AS TotalViews,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 AND u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
BadgeStats AS (
    SELECT b.UserId, 
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.TagBased = 1 THEN 1 END) AS TagBadges,
           STRING_AGG(b.Name, ', ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
PostTags AS (
    SELECT p.Id, p.OwnerUserId, 
           UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
           p.Score, p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT pt.OwnerUserId, pt.Tag,
           COUNT(*) AS TagUsage,
           AVG(pt.Score) AS AvgTagScore,
           RANK() OVER (PARTITION BY pt.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM PostTags pt
    GROUP BY pt.OwnerUserId, pt.Tag
),
CommentStats AS (
    SELECT c.UserId,
           COUNT(*) AS NumComments,
           AVG(LENGTH(c.Text)) AS AvgCommentLength,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
)
SELECT us.Id, us.Reputation, us.NumPosts, us.NumQuestions, us.AvgPostScore,
       COALESCE(us.TotalViews, 0) AS TotalViews, us.RepRank,
       bs.GoldBadges, bs.TagBadges, bs.BadgeList,
       tt.Tag AS TopTag, tt.TagUsage, tt.AvgTagScore,
       cs.NumComments, cs.AvgCommentLength, cs.LastCommentDate,
       CASE WHEN us.NumQuestions > 0 THEN ROUND(us.NumPosts * 1.0 / us.NumQuestions, 2) ELSE NULL END AS PostsPerQuestion,
       CASE WHEN cs.NumComments IS NOT NULL THEN us.Reputation / cs.NumComments ELSE NULL END AS RepPerComment
FROM UserStats us
LEFT OUTER JOIN BadgeStats bs ON us.Id = bs.UserId
LEFT OUTER JOIN TopTags tt ON us.Id = tt.OwnerUserId AND tt.TagRank = 1
LEFT OUTER JOIN CommentStats cs ON us.Id = cs.UserId
WHERE EXISTS (
    SELECT 1 FROM Votes v WHERE v.UserId = us.Id AND v.VoteTypeId IN (2,3)
)
AND us.RepRank <= 500
AND (bs.GoldBadges IS NOT NULL OR cs.NumComments > 10)
UNION ALL
SELECT NULL AS Id, NULL AS Reputation, NULL AS NumPosts, NULL AS NumQuestions, NULL AS AvgPostScore,
       SUM(us.TotalViews) AS TotalViews, NULL AS RepRank,
       NULL AS GoldBadges, NULL AS TagBadges, 'AGGREGATE' AS BadgeList,
       NULL AS TopTag, NULL AS TagUsage, NULL AS AvgTagScore,
       NULL AS NumComments, NULL AS AvgCommentLength, NULL AS LastCommentDate,
       NULL AS PostsPerQuestion, NULL AS RepPerComment
FROM UserStats us
ORDER BY TotalViews DESC NULLS LAST, RepRank ASC;