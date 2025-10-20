-- {"query": "35023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 801} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers
    FROM 
        Users u
        INNER JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE 
        u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
    HAVING 
        COUNT(p.Id) > 100
),
BadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY b.UserId
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(c.Id) AS CommentsCount,
        COALESCE(SUM(v1.Score),0) AS CommentScoreSum,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetVotes
    FROM 
        Posts p
        LEFT JOIN Comments c ON c.PostId = p.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN (
            SELECT PostId, SUM(Score) AS Score FROM Comments GROUP BY PostId
        ) v1 ON v1.PostId = p.Id
    GROUP BY 
        p.Id, p.OwnerUserId
),
RecentHotQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score,
        ph.CreationDate AS HotDate
    FROM 
        Posts p
        INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id AND pt.Name = 'Question'
        INNER JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 52
    WHERE 
        ph.CreationDate > CURRENT_DATE - INTERVAL '30 days'
        AND p.Score >= 5
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    COALESCE(SUM(pe.NetVotes),0) AS TotalNetVotes,
    COALESCE(SUM(pe.CommentsCount),0) AS TotalComments,
    COALESCE(SUM(pe.CommentScoreSum),0) AS TotalCommentScore,
    COUNT(DISTINCT rhq.QuestionId) AS RecentHotQuestions30Days
FROM 
    TopUsers tu
    LEFT JOIN BadgeSummary bs ON bs.UserId = tu.UserId
    LEFT JOIN PostEngagement pe ON pe.OwnerUserId = tu.UserId
    LEFT JOIN RecentHotQuestions rhq ON rhq.OwnerUserId = tu.UserId
GROUP BY
    tu.UserId, tu.DisplayName, tu.Reputation, tu.TotalPosts, tu.Questions, tu.Answers,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
ORDER BY
    RecentHotQuestions30Days DESC,
    tu.Reputation DESC,
    TotalNetVotes DESC
LIMIT 50;