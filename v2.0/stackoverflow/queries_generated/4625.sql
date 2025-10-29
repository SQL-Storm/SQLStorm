-- {"query": "4625.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1736} 

WITH RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_post,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_day_score,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_day_score
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.PostId) AS TotalPosts,
        SUM(p.PostScore) AS TotalScore,
        AVG(p.PostScore) AS AvgScore,
        MAX(p.PostScore) AS MaxScore,
        MIN(p.PostScore) AS MinScore,
        COUNT(CASE WHEN p.rn_user_post = 1 THEN 1 ELSE NULL END) AS IsMostRecentPost,
        SUM(CASE WHEN p.prev_day_score < p.PostScore AND p.next_day_score > p.PostScore THEN 1 ELSE 0 END) AS PostsWithScoreGains,
        ROUND(AVG(CAST(p.prev_day_score AS NUMERIC)) - AVG(CAST(p.next_day_score AS NUMERIC)), 2) AS AvgScoreDifferenceFromNeighbors
    FROM RankedUserPosts p
    WHERE p.PostCreationDate >= DATE('now', '-1 year')
    GROUP BY p.OwnerUserId
),
HighlyVotedAnswers AS (
    SELECT
        ans.ParentId AS QuestionId,
        COUNT(ans.Id) AS NumHighlyVotedAnswers
    FROM Posts ans
    WHERE ans.PostTypeId = 2 AND ans.Score >= 10
    GROUP BY ans.ParentId
),
QuestionsWithNoAnswers AS (
    SELECT
        q.Id AS QuestionId
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.AnswerCount = 0 AND q.ClosedDate IS NULL
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views AS UserViews,
        COALESCE(UP.TotalPosts, 0) AS UserTotalPosts,
        COALESCE(UP.TotalScore, 0) AS UserTotalScore,
        COALESCE(UP.AvgScore, 0.0) AS UserAvgScore,
        COALESCE(UP.MaxScore, 0) AS UserMaxScore,
        COALESCE(UP.MinScore, 0) AS UserMinScore,
        COALESCE(UP.IsMostRecentPost, 0) AS UserIsMostRecentPost,
        COALESCE(UP.PostsWithScoreGains, 0) AS UserPostsWithScoreGains,
        COALESCE(UP.AvgScoreDifferenceFromNeighbors, 0.0) AS UserAvgScoreDifferenceFromNeighbors,
        COUNT(DISTINCT c.Id) AS UserCommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UserUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS UserDownvotes,
        COUNT(DISTINCT b.Id) AS UserBadgeCount,
        COUNT(DISTINCT QNA.QuestionId) AS UserQuestionsWithNoAnswers,
        SUM(CASE WHEN HVA.QuestionId IS NOT NULL THEN 1 ELSE 0 END) AS UserQuestionsWithHighlyVotedAnswers
    FROM Users u
    LEFT JOIN UserPostStats UP ON u.Id = UP.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= DATE('now', '-1 year')
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= DATE('now', '-1 year') AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN QuestionsWithNoAnswers QNA ON EXISTS (SELECT 1 FROM Posts p_qna WHERE p_qna.OwnerUserId = u.Id AND p_qna.PostTypeId = 1 AND p_qna.AnswerCount = 0 AND p_qna.ClosedDate IS NULL)
    LEFT JOIN HighlyVotedAnswers HVA ON EXISTS (SELECT 1 FROM Posts p_hva WHERE p_hva.OwnerUserId = u.Id AND p_qna.PostTypeId = 1 AND EXISTS (SELECT 1 FROM HighlyVotedAnswers hv WHERE hv.QuestionId = p_hva.Id))
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.CreationDate,
    ue.UserViews,
    ue.UserTotalPosts,
    ue.UserTotalScore,
    ue.UserAvgScore,
    ue.UserMaxScore,
    ue.UserMinScore,
    ue.UserIsMostRecentPost,
    ue.UserPostsWithScoreGains,
    ue.UserAvgScoreDifferenceFromNeighbors,
    ue.UserCommentCount,
    ue.UserUpvotes,
    ue.UserDownvotes,
    ue.UserBadgeCount,
    ue.UserQuestionsWithNoAnswers,
    ue.UserQuestionsWithHighlyVotedAnswers,
    CASE
        WHEN ue.UserAvgScore > 50 THEN 'High Performer'
        WHEN ue.UserReputation > 10000 THEN 'Experienced User'
        WHEN ue.UserCommentCount > 500 THEN 'Active Commenter'
        WHEN ue.UserBadgeCount > 10 THEN 'Accomplished User'
        ELSE 'Standard User'
    END AS UserTier,
    COALESCE(MAX(p_late.Score), 0) AS MaxScoreOfLatePost,
    COUNT(DISTINCT p_older.Id) AS NumberOfOlderPosts
FROM UserEngagement ue
LEFT JOIN Posts p_late ON ue.UserId = p_late.OwnerUserId AND p_late.CreationDate BETWEEN DATE('now', '-30 days') AND DATE('now')
LEFT JOIN Posts p_older ON ue.UserId = p_older.OwnerUserId AND p_older.CreationDate < DATE('now', '-1 year')
GROUP BY
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.CreationDate,
    ue.UserViews,
    ue.UserTotalPosts,
    ue.UserTotalScore,
    ue.UserAvgScore,
    ue.UserMaxScore,
    ue.UserMinScore,
    ue.UserIsMostRecentPost,
    ue.UserPostsWithScoreGains,
    ue.UserAvgScoreDifferenceFromNeighbors,
    ue.UserCommentCount,
    ue.UserUpvotes,
    ue.UserDownvotes,
    ue.UserBadgeCount,
    ue.UserQuestionsWithNoAnswers,
    ue.UserQuestionsWithHighlyVotedAnswers
HAVING ue.UserTotalPosts > 5 OR ue.UserReputation > 5000
ORDER BY ue.UserReputation DESC, ue.UserTotalScore DESC
LIMIT 100;
