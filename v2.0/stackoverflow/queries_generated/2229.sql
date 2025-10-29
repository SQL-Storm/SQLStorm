-- {"query": "2229.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1436} 
WITH RecursiveTagStats AS (
    SELECT 
        t.Id,
        t.TagName,
        COALESCE(t.Count,0) AS TagCount,
        COALESCE(p.ViewCount,0) AS TotalViews,
        COALESCE(p.Score,0) AS TotalScore,
        COALESCE(p.AnswerCount,0) AS TotalAnswers,
        ROW_NUMBER() OVER (ORDER BY COALESCE(t.Count,0) DESC, t.TagName) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1
    WHERE t.TagName IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId IN (1,2,3)) AS PostsCreated,
        COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS PostsEdited,
        SUM(COALESCE(v.VoteCount, 0)) AS TotalVotesReceived,
        CASE 
            WHEN COUNT(DISTINCT ph.PostId) = 0 THEN 0 
            ELSE ROUND(1.0 * SUM(COALESCE(v.VoteCount, 0)) / COUNT(DISTINCT ph.PostId), 2)
        END AS AvgVotesPerPost
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount 
        FROM Votes 
        WHERE VoteTypeId IN (2,3) -- UpMod and DownMod
        GROUP BY PostId
    ) v ON v.PostId = ph.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
AnswerRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswersWithComments AS (
    SELECT
        ar.AnswerId,
        ar.QuestionId,
        ar.OwnerUserId,
        ar.Score,
        ar.AnswerRank,
        COUNT(c.Id) FILTER (WHERE c.Text IS NOT NULL AND LENGTH(c.Text) > 50) AS LongCommentsCount
    FROM AnswerRanks ar
    LEFT JOIN Comments c ON c.PostId = ar.AnswerId
    GROUP BY ar.AnswerId, ar.QuestionId, ar.OwnerUserId, ar.Score, ar.AnswerRank
    HAVING ar.AnswerRank <= 5
),
UserBadgesRanked AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.Class IN (1,2,3)
),
ClosedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        DENSE_RANK() OVER (ORDER BY p.ClosedDate) AS CloseRank,
        COALESCE(cr.Name, 'Unknown') AS CloseReasonName,
        ph.Comment AS CloseReasonIdJson
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS int) = cr.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
),
CombinedUserScore AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostsCreated,
        ua.PostsEdited,
        ua.TotalVotesReceived,
        ua.AvgVotesPerPost,
        COALESCE(sum(b.Class),0) AS BadgeScore
    FROM UserActivity ua
    LEFT JOIN Badges b ON b.UserId = ua.UserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostsCreated, ua.PostsEdited, ua.TotalVotesReceived, ua.AvgVotesPerPost
),
FinalRanking AS (
    SELECT
        cu.UserId,
        cu.DisplayName,
        cu.Reputation,
        cu.PostsCreated,
        cu.PostsEdited,
        cu.TotalVotesReceived,
        cu.AvgVotesPerPost,
        cu.BadgeScore,
        RANK() OVER (
            ORDER BY 
                cu.BadgeScore DESC,
                cu.AvgVotesPerPost DESC,
                cu.Reputation DESC
        ) AS OverallRank
    FROM CombinedUserScore cu
)
SELECT 
    fr.OverallRank,
    fr.DisplayName,
    fr.Reputation,
    fr.PostsCreated,
    fr.PostsEdited,
    fr.TotalVotesReceived,
    fr.AvgVotesPerPost,
    fr.BadgeScore,
    jsonb_agg(
        jsonb_build_object(
            'AnswerId', ta.AnswerId,
            'QuestionId', ta.QuestionId,
            'Score', ta.Score,
            'Rank', ta.AnswerRank,
            'LongComments', ta.LongCommentsCount
        ) ORDER BY ta.Score DESC
    ) FILTER (WHERE ta.AnswerId IS NOT NULL) AS TopAnswers,
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'BadgeName', ub.Name,
                'Class', CASE ub.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' ELSE 'Bronze' END,
                'Rank', ub.BadgeRank
            ) ORDER BY ub.BadgeRank
        )
        FROM UserBadgesRanked ub
        WHERE ub.UserId = fr.UserId AND ub.BadgeRank <= 3
    ) AS TopBadges,
    (
        SELECT jsonb_agg(
            jsonb_build_object(
                'QuestionId', cq.QuestionId,
                'Title', cq.Title,
                'ClosedDate', cq.ClosedDate,
                'CloseReason', cq.CloseReasonName
            ) ORDER BY cq.ClosedDate DESC
            LIMIT 3
        )
        FROM ClosedQuestions cq
        JOIN Posts p ON p.Id = cq.QuestionId
        WHERE p.OwnerUserId = fr.UserId
    ) AS RecentClosedQuestions
FROM FinalRanking fr
LEFT JOIN TopAnswersWithComments ta ON ta.OwnerUserId = fr.UserId
GROUP BY 
    fr.OverallRank,
    fr.DisplayName,
    fr.Reputation,
    fr.PostsCreated,
    fr.PostsEdited,
    fr.TotalVotesReceived,
    fr.AvgVotesPerPost,
    fr.BadgeScore
ORDER BY fr.OverallRank
LIMIT 50;