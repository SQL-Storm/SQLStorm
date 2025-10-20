-- {"query": "35087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 572} 
WITH RecentQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
      AND p.Score > 0
),
TopContributors AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COUNT(b.Id) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 0
),
EngagedQuestions AS (
    SELECT rq.QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT a.Id) AS AnswerCount
    FROM RecentQuestions rq
    LEFT JOIN Comments c ON rq.QuestionId = c.PostId
    LEFT JOIN Posts a ON a.ParentId = rq.QuestionId AND a.PostTypeId = 2
    GROUP BY rq.QuestionId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId
    HAVING COUNT(DISTINCT a.Id) > 0
),
HotTags AS (
    SELECT t.TagName, SUM(t.Count) AS TotalCount
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TotalCount DESC
    LIMIT 10
),
TagQuestionStats AS (
    SELECT 
        et.QuestionId,
        et.Title,
        et.CreationDate,
        et.Score,
        et.ViewCount,
        et.OwnerUserId,
        ht.TagName
    FROM EngagedQuestions et
    JOIN Posts p ON p.Id = et.QuestionId
    JOIN HotTags ht ON POSITION('"' || ht.TagName || '"' IN p.Tags) > 0
)
SELECT 
    tqs.TagName,
    COUNT(*) AS QuestionCount,
    AVG(tqs.Score) AS AvgScore,
    AVG(tqs.ViewCount) AS AvgViews,
    AVG(tqs.CreationDate) AS AvgCreationDateEpoch,
    MAX(tc.DisplayName) AS TopContributor,
    MAX(tc.Reputation) AS ContributorReputation,
    MAX(tc.GoldBadges) AS MaxGoldBadges
FROM TagQuestionStats tqs
LEFT JOIN TopContributors tc ON tqs.OwnerUserId = tc.UserId
GROUP BY tqs.TagName
ORDER BY AVG(tqs.ViewCount) DESC, COUNT(*) DESC
LIMIT 10;