-- {"query": "4458.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1047} 
WITH RankedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserContributions AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreQuestions,
        SUM(CASE WHEN p.AnswerCount > 5 THEN 1 ELSE 0 END) AS HighAnswerQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS RecentEditsOrComments,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 4, 5, 6, 8, 9) OR ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) OR EXISTS (SELECT 1 FROM Comments c WHERE c.UserId = ph.UserId AND c.PostId = ph.PostId)
    GROUP BY ph.UserId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(uc.TotalQuestions, 0) AS TotalQuestionsPosted,
        COALESCE(uc.PositiveScoreQuestions, 0) AS QuestionsWithPositiveScore,
        COALESCE(uc.HighAnswerQuestions, 0) AS QuestionsWithManyAnswers,
        COALESCE(ra.RecentEditsOrComments, 0) AS NumberOfRecentActivities,
        ra.LastActivityDate AS LastRecentActivity,
        CASE WHEN u.LastAccessDate < DATE('now', '-365 day') THEN 'Inactive' ELSE 'Active' END AS UserStatus
    FROM Users u
    LEFT JOIN UserContributions uc ON u.Id = uc.OwnerUserId
    LEFT JOIN RecentActivity ra ON u.Id = ra.UserId
)
SELECT
    rq.PostId,
    rq.Title,
    rq.OwnerUserId,
    rq.OwnerDisplayName,
    rq.CreationDate AS QuestionCreationDate,
    rq.Score AS QuestionScore,
    rq.AnswerCount AS QuestionAnswerCount,
    rq.ViewCount AS QuestionViewCount,
    ue.DisplayName AS EngagedUserDisplayName,
    ue.Reputation AS EngagedUserReputation,
    ue.CreationDate AS EngagedUserCreationDate,
    ue.TotalQuestionsPosted,
    ue.QuestionsWithPositiveScore,
    ue.QuestionsWithManyAnswers,
    ue.NumberOfRecentActivities,
    ue.LastRecentActivity,
    ue.UserStatus,
    CASE
        WHEN rq.Score > 1000 THEN 'HighScoring'
        WHEN rq.AnswerCount > 50 THEN 'PopularAnswered'
        WHEN rq.ViewCount > 10000 THEN 'HighlyViewed'
        ELSE 'Standard'
    END AS QuestionCategory,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId AND c.Score < 0) AS NegativeScoreComments,
    (SELECT COUNT(*) FROM PostLinks pl JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id WHERE pl.PostId = rq.PostId AND lt.Name = 'Duplicate') AS DuplicateLinks,
    (SELECT COUNT(*) FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = rq.PostId AND vt.Name IN ('UpMod', 'DownMod') AND v.UserId IS NOT NULL) AS TotalVotes,
    CASE WHEN rq.rn <= 5 THEN 'Top5Recent' ELSE 'Other' END AS UserRecentActivityRank
FROM RankedQuestions rq
JOIN UserEngagement ue ON rq.OwnerUserId = ue.UserId
WHERE rq.rn <= 10 AND ue.Reputation > 1000
ORDER BY rq.CreationDate DESC
LIMIT 50;