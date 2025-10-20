-- {"query": "20018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1100} 

WITH UserQuestionStats AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        p.Title,
        p.Tags,
        p.Score,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.CreationDate, 1) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevQuestionDate,
        COUNT(*) OVER(PARTITION BY p.OwnerUserId) as UserQuestionCount,
        AVG(p.Score) OVER(PARTITION BY p.OwnerUserId) as UserAvgQuestionScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions
      AND p.ClosedDate IS NULL
      AND u.Reputation > 1000
),
UserBadgePivots AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PrimaryUserSet AS (
    SELECT *
    FROM UserQuestionStats
    WHERE rn = 1 AND UserQuestionCount >= 5
),
SecondaryUserSet AS (
    -- Find the latest question from users who have edited at least 100 posts,
    -- regardless of their question count, to test the UNION logic.
    SELECT uqs.*
    FROM UserQuestionStats uqs
    WHERE uqs.rn = 1
      AND uqs.OwnerUserId IN (
        SELECT UserId
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, or Tags
        GROUP BY UserId
        HAVING COUNT(*) >= 100
      )
),
CombinedUserLatestQuestion AS (
    SELECT * FROM PrimaryUserSet
    UNION
    SELECT * FROM SecondaryUserSet
)
SELECT
    c.DisplayName,
    c.Reputation,
    c.Title AS LatestQuestionTitle,
    REPLACE(SUBSTRING(c.Tags, 2, LENGTH(c.Tags) - 2), '><', ', ') AS Tags,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.UserQuestionCount,
    c.UserAvgQuestionScore,
    (c.Score - c.UserAvgQuestionScore) / NULLIF(c.UserAvgQuestionScore, 0) AS ScoreDeviation,
    c.CreationDate - c.PrevQuestionDate AS TimeBetweenQuestions,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    aa.Id AS AcceptedAnswerId,
    aa.Score AS AcceptedAnswerScore,
    aa.CreationDate AS AcceptedAnswerDate,
    ans_user.DisplayName AS AnswererName,
    ans_user.Reputation AS AnswererReputation,
    aa.CreationDate - c.CreationDate AS TimeToAccept,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.Id) AS QuestionCommentCount,
    (
        -- Correlated subquery: check if the question has ever been linked to as a duplicate
        SELECT CASE WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.RelatedPostId = c.Id AND pl.LinkTypeId = 3
        ) THEN 'TRUE' ELSE 'FALSE' END
    ) AS IsMarkedAsDuplicateOf,
    (
        -- Correlated subquery: count edits by users other than the owner
        SELECT COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        WHERE ph.PostId = c.Id
          AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Any edit or rollback
          AND ph.UserId != c.OwnerUserId
    ) AS EditsByOthers
FROM CombinedUserLatestQuestion c
LEFT JOIN UserBadgePivots b ON c.OwnerUserId = b.UserId
LEFT JOIN Posts aa ON c.AcceptedAnswerId = aa.Id AND aa.PostTypeId = 2
LEFT JOIN Users ans_user ON aa.OwnerUserId = ans_user.Id
ORDER BY
    c.Reputation DESC,
    TimeToAccept ASC NULLS LAST,
    c.Score DESC
LIMIT 500;
