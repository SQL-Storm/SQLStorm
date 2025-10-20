-- {"query": "49044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1333} 

WITH QuestionCloseReasons AS (
    -- Finds the most recent close reason for each question that has been closed.
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        crt.Name AS CloseReasonName
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment = crt.Id::varchar -- Comment stores CloseReasonId as varchar
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed event
    ORDER BY ph.PostId, ph.CreationDate DESC -- Get the latest close reason if multiple close/reopen events occurred
),
QuestionEditCounts AS (
    -- Counts the number of distinct edit actions (title, body, tags) for each post.
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
),
PopularDuplicateQuestions AS (
    -- Identifies questions that are popular, have many edits, and were closed as duplicates.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        q.AcceptedAnswerId,
        qec.EditCount,
        -- Extracts tags into an array for potential future tag-based analysis or further complexity
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><') AS TagArray
    FROM Posts q
    INNER JOIN QuestionCloseReasons qcr ON q.Id = qcr.PostId
    INNER JOIN QuestionEditCounts qec ON q.Id = qec.PostId
    WHERE
        q.PostTypeId = 1 -- Must be a question
        AND q.OwnerUserId IS NOT NULL -- Must have an owner
        AND qcr.CloseReasonName = 'Duplicate' -- Specifically closed as a duplicate
        AND q.ViewCount > 20000 -- Threshold for high view count
        AND q.AnswerCount >= 15 -- Threshold for many answers
        AND q.FavoriteCount >= 30 -- Threshold for many favorites
        AND qec.EditCount >= 7 -- Threshold for significant edits
),
UserSelfAcceptedAnswers AS (
    -- Identifies questions where the owner accepted their own answer.
    SELECT
        q.Id AS QuestionId,
        1 AS HasSelfAcceptedAnswer
    FROM Posts q
    JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
      AND q.AcceptedAnswerId IS NOT NULL
      AND q.OwnerUserId = a.OwnerUserId
),
UserBadgesSummary AS (
    -- Aggregates badge information for each user, counting gold and tag-based gold badges.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 1 AND b.TagBased = TRUE THEN b.Id END) AS TagBasedGoldBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT pdq.QuestionId) AS NumPopularDuplicateQuestions,
    SUM(pdq.ViewCount) AS TotalViewCountOfPopularDuplicateQuestions,
    SUM(pdq.AnswerCount) AS TotalAnswerCountOfPopularDuplicateQuestions,
    SUM(pdq.FavoriteCount) AS TotalFavoriteCountOfPopularDuplicateQuestions,
    MAX(CASE WHEN usaa.HasSelfAcceptedAnswer IS NOT NULL THEN 1 ELSE 0 END) AS HasSelfAcceptedAnswerInAnyPQ,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadgesCount,
    COALESCE(ubs.TagBasedGoldBadges, 0) AS TagBasedGoldBadgesCount,
    -- A composite score to rank users based on various influence and activity metrics.
    (u.Reputation * 0.05) + -- Reputation has a strong base influence
    (COALESCE(ubs.GoldBadges, 0) * 15) + -- Gold badges show significant achievement
    (COALESCE(ubs.TagBasedGoldBadges, 0) * 25) + -- Tag-based gold badges are highly specialized
    (SUM(pdq.ViewCount) * 0.00005) + -- Contribution from question visibility
    (SUM(pdq.AnswerCount) * 0.75) + -- Contribution from answers received on their questions
    (SUM(pdq.FavoriteCount) * 1.2) + -- Contribution from questions being favorited
    (COUNT(DISTINCT pdq.QuestionId) * 75) + -- Strong weight for number of impactful questions
    (MAX(CASE WHEN usaa.HasSelfAcceptedAnswer IS NOT NULL THEN 1 ELSE 0 END) * 10) -- Small bonus for self-accepted answers
    AS InfluenceScore
FROM Users u
INNER JOIN PopularDuplicateQuestions pdq ON u.Id = pdq.OwnerUserId
LEFT JOIN UserSelfAcceptedAnswers usaa ON pdq.QuestionId = usaa.QuestionId
LEFT JOIN UserBadgesSummary ubs ON u.Id = ubs.UserId
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    COALESCE(ubs.GoldBadges, 0),
    COALESCE(ubs.TagBasedGoldBadges, 0)
ORDER BY InfluenceScore DESC, u.Reputation DESC
LIMIT 25;
