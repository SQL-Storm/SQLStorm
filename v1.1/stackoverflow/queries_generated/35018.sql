-- {"query": "35018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 741} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
        AND COUNT(DISTINCT b.Id) > 10
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
    HAVING COUNT(DISTINCT a.Id) > 2 AND SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 5
),
MergedHistory AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS InitialTitleDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate END) AS LastEditedTitleDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1,4,5)
    GROUP BY ph.PostId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    rq.QuestionId,
    rq.Title,
    rq.Score AS QuestionScore,
    rq.ViewCount AS QuestionViews,
    rq.AnswerCount,
    rq.Upvotes,
    rq.Downvotes,
    mh.InitialTitleDate,
    mh.LastEditedTitleDate,
    mh.BodyEditCount,
    EXTRACT(EPOCH FROM (mh.LastEditedTitleDate - mh.InitialTitleDate))/60 AS TitleEditLatencyMins
FROM TopUsers tu
JOIN RecentQuestions rq ON rq.OwnerUserId = tu.UserId
LEFT JOIN MergedHistory mh ON mh.PostId = rq.QuestionId
ORDER BY
    tu.Reputation DESC,
    rq.ViewCount DESC,
    TitleEditLatencyMins ASC
LIMIT 100;