-- {"query": "4722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1322}
WITH RankedAnswers AS (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        p.OwnerUserId AS AnswerOwnerUserId,
        u.Reputation AS AnswerOwnerReputation,
        u.DisplayName AS AnswerOwnerDisplayName,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS AnswerCommentCount,
        CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM Posts AS p
    JOIN Posts AS q ON p.ParentId = q.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
      AND q.PostTypeId = 1
      AND q.ClosedDate IS NULL
      AND p.OwnerUserId IS NOT NULL
      AND p.Score >= 0
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount AS QuestionAnswerCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.OwnerUserId AS QuestionOwnerUserId,
        u_q.Reputation AS QuestionOwnerReputation,
        u_q.DisplayName AS QuestionOwnerDisplayName,
        (SELECT COUNT(*) FROM Comments AS qc WHERE qc.PostId = q.Id) AS QuestionCommentCount,
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory AS ph
            WHERE ph.PostId = q.Id
              AND ph.PostHistoryTypeId IN (10, 19)
        ) AS QuestionClosureOrProtectionCount,
        SUBSTRING(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags) - 2)) AS QuestionTags
    FROM Posts AS q
    LEFT JOIN Users AS u_q ON q.OwnerUserId = u_q.Id
    WHERE q.PostTypeId = 1
      AND q.ClosedDate IS NULL
      AND q.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS PostCount,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(Score) AS AvgPostScore,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT
    qs.QuestionId,
    qs.QuestionTitle,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.QuestionViewCount,
    qs.QuestionFavoriteCount,
    qs.QuestionOwnerDisplayName,
    qs.QuestionOwnerReputation,
    qs.QuestionCommentCount,
    qs.QuestionClosureOrProtectionCount,
    qs.QuestionTags,
    ra_best.AnswerId AS BestAnswerId,
    ra_best.AnswerScore AS BestAnswerScore,
    ra_best.AnswerCreationDate AS BestAnswerCreationDate,
    ra_best.AnswerOwnerDisplayName AS BestAnswerOwnerDisplayName,
    ra_best.AnswerOwnerReputation AS BestAnswerOwnerReputation,
    ra_best.AnswerCommentCount AS BestAnswerCommentCount,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = qs.QuestionId AND v.VoteTypeId = 2) AS QuestionUpVotes,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = qs.QuestionId AND v.VoteTypeId = 3) AS QuestionDownVotes,
    COALESCE(ua.PostCount, 0) AS OwnerTotalPosts,
    COALESCE(ua.QuestionCount, 0) AS OwnerQuestions,
    COALESCE(ua.AnswerCount, 0) AS OwnerAnswers,
    CASE
        WHEN qs.QuestionTags LIKE '%<sql>%' THEN 'SQL Related'
        WHEN qs.QuestionTags LIKE '%<performance>%' THEN 'Performance Related'
        ELSE 'Other'
    END AS TagCategory,
    CASE
        WHEN qs.QuestionScore > 1000 THEN 'High Score'
        WHEN qs.QuestionScore BETWEEN 100 AND 1000 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - qs.QuestionCreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
    qs.QuestionAnswerCount,
    (SELECT COUNT(*) FROM PostLinks AS pl WHERE pl.PostId = qs.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinksToThisQuestion,
    COALESCE(TOP_N.TopAnswerRank, 999) AS TopAnswerRank,
    COALESCE(qs.QuestionOwnerDisplayName, 'Community') AS DisplayOwnerName
FROM QuestionStats AS qs
LEFT JOIN RankedAnswers AS ra_best ON qs.QuestionId = ra_best.QuestionId AND ra_best.rn = 1
LEFT JOIN UserActivity AS ua ON qs.QuestionOwnerUserId = ua.UserId
LEFT JOIN (
    SELECT
        ra.QuestionId,
        ra.rn AS TopAnswerRank
    FROM RankedAnswers AS ra
    WHERE ra.rn BETWEEN 1 AND 5
) AS TOP_N ON qs.QuestionId = TOP_N.QuestionId
ORDER BY qs.QuestionCreationDate DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;