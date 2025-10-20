-- {"query": "18096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1268} 
WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
PostEditHistory AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
),
QuestionAnswerRatio AS (
    SELECT
        ups.OwnerUserId,
        CAST(ups.QuestionCount AS REAL) / NULLIF(ups.AnswerCount, 0) AS QARatio
    FROM UserPostStats ups
    WHERE ups.AnswerCount > 0
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.QuestionCount, 0) AS QuestionCount,
        COALESCE(ups.AnswerCount, 0) AS AnswerCount,
        COALESCE(ups.AverageScore, 0.0) AS AveragePostScore,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AverageCommentScore, 0.0) AS AverageCommentScore,
        COALESCE(uvs.TotalUpVotes, 0) AS TotalUpVotes,
        COALESCE(uvs.TotalDownVotes, 0) AS TotalDownVotes,
        COALESCE(peh.EditCount, 0) AS TotalEdits,
        COALESCE(qar.QARatio, 0.0) AS QuestionAnswerRatio,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRankByReputation
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
    LEFT JOIN PostEditHistory peh ON u.Id = peh.PostId
    LEFT JOIN QuestionAnswerRatio qar ON u.Id = qar.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> '' AND u.CreationDate > '2010-01-01'
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.QuestionCount,
    ue.AnswerCount,
    ROUND(ue.AveragePostScore, 2) AS RoundedAveragePostScore,
    ue.TotalComments,
    ROUND(ue.AverageCommentScore, 2) AS RoundedAverageCommentScore,
    ue.TotalUpVotes,
    ue.TotalDownVotes,
    ue.TotalEdits,
    CASE
        WHEN ue.QuestionAnswerRatio = 0.0 THEN 'No Answers'
        WHEN ue.QuestionAnswerRatio > 5 THEN 'High Question Ratio'
        WHEN ue.QuestionAnswerRatio < 0.2 THEN 'High Answer Ratio'
        ELSE 'Balanced Ratio'
    END AS RatioCategory,
    ue.UserRankByReputation,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ue.UserId AND b.Class = 1) AS GoldBadgeCount,
    COALESCE(p.Title, 'N/A') AS MostRecentPostTitle,
    CASE
        WHEN ue.TotalPosts > 1000 AND ue.TotalComments > 500 AND ue.TotalUpVotes > 2000 AND ue.TotalDownVotes < 100 AND ue.UserRankByReputation <= 50
        THEN 'Highly Engaged Power User'
        WHEN ue.TotalPosts > 500 AND ue.TotalComments > 200 AND ue.AveragePostScore > 5.0
        THEN 'Experienced Contributor'
        ELSE 'Standard User'
    END AS UserProfileCategory
FROM UserEngagement ue
LEFT JOIN Posts p ON ue.UserId = p.OwnerUserId AND p.Id = (
    SELECT Id FROM Posts WHERE OwnerUserId = ue.UserId ORDER BY LastActivityDate DESC LIMIT 1
)
WHERE ue.Reputation > 10000
ORDER BY ue.UserRankByReputation, ue.DisplayName
LIMIT 100;