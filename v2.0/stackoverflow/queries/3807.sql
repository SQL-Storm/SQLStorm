-- {"query": "3807.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3057} 
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS VoteBalance,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        COALESCE(SUM(p.ViewCount),0) AS TotalViews,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags IS NOT NULL
       AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName, t.Count
),
RecentClosedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        ph.Comment AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostHistory ph
        ON ph.PostId = p.Id
       AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NOT NULL
),
TopUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        (us.QuestionCount + us.AnswerCount) AS TotalContributions,
        RANK() OVER (ORDER BY us.Reputation DESC) AS RepRank
    FROM UserStats us
    WHERE us.Reputation > 0
)
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalContributions,
    tu.RepRank,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(tp.TagName,'N/A') AS TopTag,
    COALESCE(tp.TagUseCount,0) AS TopTagUse,
    rc.Title AS RecentClosedQuestion,
    rc.CloseReason
FROM TopUsers tu
LEFT JOIN UserStats us ON us.Id = tu.Id
LEFT JOIN (
    SELECT TagName, TagUseCount
    FROM TagPopularity
    ORDER BY TagRank
    LIMIT 1
) tp ON 1=1
LEFT JOIN (
    SELECT Title, CloseReason
    FROM RecentClosedQuestions
    WHERE rn = 1
    ORDER BY ClosedDate DESC
    LIMIT 1
) rc ON 1=1
WHERE (tu.RepRank <= 100 OR tu.TotalContributions > 500)
  AND (us.GoldBadges > 0 OR us.SilverBadges > 5)
  AND (rc.Title IS NOT NULL OR tp.TagUseCount > 1000)

UNION ALL

SELECT
    NULL AS Id,
    'Aggregate Summary' AS DisplayName,
    NULL AS Reputation,
    NULL AS TotalContributions,
    NULL AS RepRank,
    SUM(us.GoldBadges) AS GoldBadges,
    SUM(us.SilverBadges) AS SilverBadges,
    SUM(us.BronzeBadges) AS BronzeBadges,
    NULL AS TopTag,
    NULL AS TopTagUse,
    NULL AS RecentClosedQuestion,
    NULL AS CloseReason
FROM UserStats us
WHERE us.Reputation > 10000;