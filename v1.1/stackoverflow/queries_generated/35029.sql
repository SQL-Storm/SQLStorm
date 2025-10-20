-- {"query": "35029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 761} 
WITH HighRepUsers AS (
    SELECT Id AS UserId, DisplayName
    FROM Users
    WHERE Reputation > 20000
),
RecentQuestions AS (
    SELECT p.Id AS QuestionId, p.OwnerUserId, p.CreationDate, p.Score, p.Title, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '90 days'
),
TopTagQuestions AS (
    SELECT rq.*, unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
    FROM RecentQuestions rq
),
PopularTags AS (
    SELECT TagName, COUNT(*) AS QuestionCount
    FROM TopTagQuestions
    GROUP BY TagName
    HAVING COUNT(*) >= 20
),
TagQuestionStats AS (
    SELECT ttq.TagName, COUNT(DISTINCT ttq.QuestionId) AS TotalQuestions, AVG(ttq.Score) AS AvgScore
    FROM TopTagQuestions ttq
    JOIN PopularTags pt ON ttq.TagName = pt.TagName
    GROUP BY ttq.TagName
),
ActiveComments AS (
    SELECT c.PostId, COUNT(*) AS CommentCount, MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY c.PostId
),
HotQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, ac.CommentCount, p.ViewCount
    FROM Posts p
    JOIN ActiveComments ac ON ac.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND ac.CommentCount >= 5
      AND p.ViewCount > 500
),
UserBadgeCounts AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
DupLinks AS (
    SELECT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate
)
SELECT
    hq.QuestionId,
    hq.Title,
    p.Score AS QuestionScore,
    hq.CommentCount,
    hq.ViewCount,
    u.DisplayName AS OwnerDisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ttq.TagName,
    tqs.TotalQuestions AS TotalRecentQuestionsInTag,
    tqs.AvgScore AS AvgRecentScoreInTag,
    COUNT(DISTINCT dl.RelatedPostId) AS NumDuplicatesLinked
FROM HotQuestions hq
JOIN Posts p ON hq.QuestionId = p.Id
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserBadgeCounts ub ON u.Id = ub.UserId
JOIN TopTagQuestions ttq ON ttq.QuestionId = hq.QuestionId
JOIN TagQuestionStats tqs ON tqs.TagName = ttq.TagName
LEFT JOIN DupLinks dl ON dl.PostId = hq.QuestionId
GROUP BY hq.QuestionId, hq.Title, p.Score, hq.CommentCount, hq.ViewCount, u.DisplayName, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ttq.TagName, tqs.TotalQuestions, tqs.AvgScore
ORDER BY hq.ViewCount DESC, hq.CommentCount DESC
LIMIT 100;