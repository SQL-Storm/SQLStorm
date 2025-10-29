-- {"query": "2349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1701} 

WITH
-- CTE to get top users by reputation and their badge counts filtered by class and tag-based
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 AND b.TagBased = 0 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 AND b.TagBased = 0 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 AND b.TagBased = 0 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- CTE for questions with tag counts and extraction of tags array
QuestionsWithTags AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        CARDINALITY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
-- CTE to find the best answer for questions (highest score with non-null owner)
BestAnswers AS (
    SELECT DISTINCT ON (ParentId)
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
),
-- CTE to compute cumulative votes on posts per vote types to include null handling and complex predicates
PostVotes AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount ELSE 0 END), 0) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId
),
-- CTE to get recent activity on posts using window functions for ranking edits
PostRecentActivity AS (
    SELECT
        ph.PostId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.UserDisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS ActivityRank
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)
),
-- CTE for detecting questions closed recently with close reasons and owner info using outer joins
RecentClosedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        ph.CreationDate AS ClosedDate,
        crt.Name AS CloseReason
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE p.PostTypeId = 1
      AND ph.CreationDate > NOW() - INTERVAL '90 days'
),
-- CTE to explode tag arrays into rows for aggregation and string expressions with NULL logic
ExplodedTags AS (
    SELECT
        q.QuestionId,
        UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS Tag
    FROM QuestionsWithTags q
),
-- CTE to get distinct tags and their question counts, with null-safe tags filtering nonsense
TagUsage AS (
    SELECT
        Tag,
        COUNT(DISTINCT QuestionId) AS QuestionCount
    FROM ExplodedTags
    WHERE Tag IS NOT NULL AND Tag <> ''
    GROUP BY Tag
),
-- CTE for tag gap detection (tags with zero questions) by left anti-join
UnusedTags AS (
    SELECT t.TagName
    FROM Tags t
    LEFT JOIN TagUsage tu ON t.TagName = tu.Tag
    WHERE tu.Tag IS NULL
),
-- Recursive CTE to generate a series of dates to join with posts for date based analytics
DateSeries(date_day) AS (
    SELECT CURRENT_DATE - INTERVAL '29 days'
    UNION ALL
    SELECT date_day + INTERVAL '1 day'
    FROM DateSeries
    WHERE date_day < CURRENT_DATE
)
SELECT
    tu.DisplayName AS UserName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionCreated,
    q.Score AS QuestionScore,
    q.ViewCount AS QuestionViews,
    q.AnswerCount,
    q.TagCount,
    ba.AnswerId AS BestAnswerId,
    ba.AnswerOwnerId,
    ba.AnswerScore,
    pv.Upvotes,
    pv.Downvotes,
    pv.TotalBounty,
    rcc.ClosedDate,
    rcc.CloseReason,
    -- Aggregated list of tags per question with concatenation and string expression with NULL-aware COALESCE
    COALESCE(
        (
            SELECT string_agg(tu2.Tag, ', ' ORDER BY tu2.Tag)
            FROM ExplodedTags tu2
            WHERE tu2.QuestionId = q.QuestionId
        ), '(no tags)'
    ) AS QuestionTags,
    -- Window function computing the rank of question score among questions created on the same day
    RANK() OVER (PARTITION BY DATE(q.CreationDate) ORDER BY q.Score DESC) AS DailyQuestionScoreRank,
    -- Number of edits from PostHistory in the last 30 days for the question
    (
        SELECT COUNT(*)
        FROM PostHistory ph2
        WHERE ph2.PostId = q.QuestionId
          AND ph2.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
          AND ph2.PostHistoryTypeId IN (4,5,6)
    ) AS RecentEditCount,
    -- String expression showing owner user display name or fallback to 'Community' or 'Deleted'
    COALESCE(u.DisplayName, CASE WHEN q.OwnerUserId IS NULL OR q.OwnerUserId = -1 THEN 'Community' ELSE 'Deleted User' END) AS QuestionOwnerDisplayName,
    -- Calculate the ratio of upvotes to downvotes with null logic and zero division protection
    CASE WHEN pv.Downvotes = 0 THEN NULL ELSE ROUND(CAST(pv.Upvotes AS NUMERIC)/pv.Downvotes, 2) END AS UpvotesDownvotesRatio
FROM TopUsers tu
INNER JOIN QuestionsWithTags q ON q.OwnerUserId = tu.Id
LEFT JOIN BestAnswers ba ON ba.QuestionId = q.QuestionId AND ba.rn = 1
LEFT JOIN PostVotes pv ON pv.PostId = q.QuestionId
LEFT JOIN RecentClosedQuestions rcc ON rcc.QuestionId = q.QuestionId
LEFT JOIN Users u ON u.Id = q.OwnerUserId
WHERE q.Score > 0
  AND q.AnswerCount > 0
  AND tu.GoldBadges > 0
ORDER BY
    tu.Reputation DESC,
    q.Score DESC,
    q.CreationDate DESC
LIMIT 100;
