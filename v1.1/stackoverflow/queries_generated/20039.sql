-- {"query": "20039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1304} 

WITH QuestionAuthors AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) OVER (PARTITION BY u.Id) AS TotalQuestions,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgQuestionScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 -- Questions
      AND u.Reputation > 1000
      AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
),
RankedQuestions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS rn_views,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) AS score_quartile,
        LEAD(p.CreationDate, 1, NOW()) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_question_date
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserBadgeStats AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Correlated subquery to find the most recent non-tag-based badge
        (SELECT b2.Name
         FROM Badges b2
         WHERE b2.UserId = b.UserId AND b2.TagBased = false
         ORDER BY b2.Date DESC
         LIMIT 1) AS LastNamedBadge
    FROM Badges b
    GROUP BY b.UserId
),
CombinedUserData AS (
    -- Users with high average scores
    SELECT UserId, DisplayName, 'High Scorer' AS UserType
    FROM QuestionAuthors
    WHERE AvgQuestionScore > 25
    GROUP BY UserId, DisplayName

    UNION ALL

    -- Users with many tag-based silver badges
    SELECT b.UserId, u.DisplayName, 'Tag Specialist' AS UserType
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Class = 2 AND b.TagBased = true
    GROUP BY b.UserId, u.DisplayName
    HAVING COUNT(b.Id) > 10
)
SELECT
    qa.UserId,
    qa.DisplayName,
    qa.Reputation,
    qa.TotalQuestions,
    CAST(qa.AvgQuestionScore AS DECIMAL(10, 2)) AS AvgScore,
    rq.Title AS TopViewedQuestionTitle,
    rq.ViewCount AS TopViewedQuestionViews,
    EXTRACT(EPOCH FROM (rq.next_question_date - rq.CreationDate)) / 3600 AS HoursUntilNextQuestion,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    ubs.LastNamedBadge,
    -- Complicated expression with NULL logic
    (ubs.GoldBadges * 10 + ubs.SilverBadges * 5 + ubs.BronzeBadges) / NULLIF(qa.Reputation / 1000.0, 0) AS BadgePointsPerKRep,
    -- String manipulation on tags
    array_length(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'), 1) AS TagCountOnTopPost,
    CASE
        WHEN rq.AcceptedAnswerId IS NOT NULL THEN 'Has Accepted Answer'
        WHEN rq.AnswerCount > 0 THEN 'Has Answers, None Accepted'
        ELSE 'No Answers'
    END AS AcceptanceStatus,
    aa_owner.DisplayName AS AcceptedAnswererName,
    aa_post.Score AS AcceptedAnswerScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentsOnTopQuestion,
    cud.UserType AS InterestingUserType
FROM QuestionAuthors qa
JOIN RankedQuestions rq ON qa.UserId = rq.OwnerUserId AND rq.rn_views = 1
LEFT JOIN UserBadgeStats ubs ON qa.UserId = ubs.UserId
LEFT JOIN Posts aa_post ON rq.AcceptedAnswerId = aa_post.Id
LEFT JOIN Users aa_owner ON aa_post.OwnerUserId = aa_owner.Id
LEFT JOIN CombinedUserData cud ON qa.UserId = cud.UserId
WHERE
    qa.TotalQuestions > 5
    AND qa.AvgQuestionScore > 2.0
    AND (ubs.GoldBadges > 0 OR qa.Reputation > 50000)
    AND EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = rq.PostId
          AND ph.PostHistoryTypeId = 10 -- Post Closed
          AND ph.Comment = '101' -- Duplicate
    )
ORDER BY
    BadgePointsPerKRep DESC NULLS LAST,
    qa.Reputation DESC
LIMIT 200;
