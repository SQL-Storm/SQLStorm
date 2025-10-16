-- {"query": "3068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1132} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT OUTER JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoryCounts AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,24)
    GROUP BY ph.PostId
),
ActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(h.EditCount, 0) AS NumberOfEdits
    FROM Posts p
    LEFT JOIN PostHistoryCounts h ON p.Id = h.PostId
    WHERE p.PostTypeId = 1
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.Tags,
        q.LastActivityDate,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(vote.Score) FROM Votes vote WHERE vote.PostId IN (SELECT Id FROM Posts a WHERE a.ParentId = q.Id) AND vote.VoteTypeId IN (2,3)) AS AvgAnswerScore
    FROM Posts q
    WHERE q.PostTypeId = 1
),
CrossReference AS (
    SELECT
        a.QuestionId,
        a.Title AS QuestionTitle,
        a.LastActivityDate,
        string_agg(DISTINCT l.RelatedPostId::text, ',') AS LinkedPosts,
        string_agg(DISTINCT c.UserDisplayName, ',') AS Commenters
    FROM ActiveQuestions a
    LEFT JOIN PostLinks l ON a.QuestionId = l.PostId AND l.LinkTypeId = 1 -- Linked
    LEFT JOIN Comments c ON a.QuestionId = c.PostId
    GROUP BY a.QuestionId, a.Title, a.LastActivityDate
),
ComplexCalculations AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        GREATEST(p.Score * 1.0 / NULLIF(p.ViewCount,0), 0) AS ScorePerView,
        CASE WHEN p.AnswerCount > 0 THEN p.AnswerCount ELSE NULL END AS ValidAnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        ROUND((SELECT AVG(COALESCE(vote.BountyAmount,0)) FROM Votes vote WHERE vote.PostId = p.Id AND vote.VoteTypeId IN (8,9)), 2) AS AvgBounty
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    up.UserId,
    up.DisplayName,
    up.TotalPosts,
    up.TotalComments,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ai.Title AS QuestionTitle,
    ai.CreationDate AS QuestionDate,
    ai.LastPostDate,
    ai.Score,
    ai.ViewCount,
    ai.AnswerCount,
    ai.CommentCount,
    ai.Tags,
    hac.EditCount,
    qas.AnswerCount AS TotalAnswers,
    qas.AvgAnswerScore,
    cr.LinkedPosts,
    cr.Commenters,
    cc.ScorePerView,
    cc.UpVotes,
    cc.DownVotes,
    cc.AvgBounty
FROM UserActivity up
LEFT JOIN BadgeSummary ub ON up.UserId = ub.UserId
LEFT JOIN ActiveQuestions ai ON up.UserId = ai.OwnerUserId
LEFT JOIN PostHistoryCounts hac ON ai.Id = hac.PostId
LEFT JOIN QuestionAnswerStats qas ON ai.Id = qas.QuestionId
LEFT JOIN CrossReference cr ON ai.Id = cr.QuestionId
LEFT JOIN ComplexCalculations cc ON ai.Id = cc.Id
WHERE (up.Reputation IS NOT NULL) AND (up.TotalPosts > 0 OR up.TotalComments > 0)
ORDER BY up.Reputation DESC, up.UserId
LIMIT 50;