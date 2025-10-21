-- {"query": "35081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 721} 
WITH top_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 100
),
post_activity AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId AND b.Date BETWEEN p.CreationDate AND (p.CreationDate + interval '30 days')
    GROUP BY p.Id, p.OwnerUserId
),
hot_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.ViewCount,
        p.Score,
        pa.CommentCount,
        pa.VoteCount,
        pa.UpVotes,
        pa.DownVotes,
        pa.BadgeCount
    FROM Posts p
    JOIN post_activity pa ON pa.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
      AND p.ViewCount > 1000
      AND p.Score > 10
),
user_question_stats AS (
    SELECT
        tu.UserId,
        COUNT(hq.QuestionId) AS HotQuestionsCount,
        AVG(hq.ViewCount) AS AvgHotQuestionViews,
        SUM(hq.VoteCount) AS TotalHotQuestionVotes,
        SUM(hq.UpVotes) AS TotalHotQuestionUpvotes,
        SUM(hq.BadgeCount) AS BadgesOnHotQuestions
    FROM top_users tu
    LEFT JOIN hot_questions hq ON hq.OwnerUserId = tu.UserId
    GROUP BY tu.UserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.QuestionsAsked,
    tu.AnswersGiven,
    tu.TotalPostScore,
    tu.TotalViews,
    uqs.HotQuestionsCount,
    uqs.AvgHotQuestionViews,
    uqs.TotalHotQuestionVotes,
    uqs.TotalHotQuestionUpvotes,
    uqs.BadgesOnHotQuestions
FROM top_users tu
LEFT JOIN user_question_stats uqs ON uqs.UserId = tu.UserId
ORDER BY (uqs.HotQuestionsCount * 10 + uqs.TotalHotQuestionUpvotes * 2 + tu.TotalPostScore) DESC
LIMIT 50;