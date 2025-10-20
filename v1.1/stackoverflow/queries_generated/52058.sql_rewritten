-- {"query": "52058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 866} 
WITH QuestionStats AS (
    SELECT p.Id, 
           p.Title, 
           p.ViewCount, 
           p.Score AS QuestionScore, 
           COUNT(DISTINCT a.Id) AS AnswerCount, 
           COALESCE(AVG(a.Score), 0) AS AvgAnswerScore, 
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
           STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS TagArray
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId IN (p.Id, a.Id)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score, p.Tags
),
UserContributions AS (
    SELECT u.Id, 
           u.Reputation, 
           u.CreationDate, 
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsPosted,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersPosted,
           COALESCE(SUM(b.BadgeCount), 0) AS TotalBadges,
           COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
           COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
           COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (SELECT UserId, COUNT(*) AS BadgeCount, Class FROM Badges GROUP BY UserId, Class) b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
CommentActivity AS (
    SELECT c.PostId, COUNT(c.Id) AS CommentCount, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
RankedQuestions AS (
    SELECT qs.Id,
           qs.Title,
           qs.ViewCount,
           qs.QuestionScore,
           qs.AnswerCount,
           qs.AvgAnswerScore,
           qs.Upvotes,
           qs.Downvotes,
           qs.TagArray,
           ca.CommentCount,
           ca.AvgCommentScore,
           uc.Reputation,
           uc.QuestionsPosted,
           uc.AnswersPosted,
           uc.TotalBadges,
           uc.GoldBadges,
           uc.SilverBadges,
           uc.BronzeBadges,
           ROW_NUMBER() OVER (PARTITION BY qs.TagArray[1] ORDER BY qs.Upvotes DESC, qs.ViewCount DESC) AS RankInTopTag
    FROM QuestionStats qs
    JOIN UserContributions uc ON uc.Id IN (SELECT OwnerUserId FROM Posts WHERE Id = qs.Id)
    LEFT JOIN CommentActivity ca ON ca.PostId = qs.Id
    WHERE qs.ViewCount > 1000
)
SELECT rq.Id,
       rq.Title,
       rq.ViewCount,
       rq.QuestionScore,
       rq.AnswerCount,
       rq.AvgAnswerScore,
       rq.Upvotes,
       rq.Downvotes,
       rq.TagArray[1] AS PrimaryTag,
       rq.CommentCount,
       rq.AvgCommentScore,
       rq.Reputation,
       rq.QuestionsPosted,
       rq.AnswersPosted,
       rq.TotalBadges,
       rq.GoldBadges,
       rq.SilverBadges,
       rq.BronzeBadges,
       rq.RankInTopTag
FROM RankedQuestions rq
WHERE rq.RankInTopTag <= 5
ORDER BY rq.Upvotes DESC, rq.ViewCount DESC
LIMIT 100;