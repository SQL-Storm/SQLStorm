-- {"query": "2014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1489} 

WITH RecentActivePosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate > CURRENT_DATE - INTERVAL '60 days'
      AND p.Score IS NOT NULL
      AND p.ViewCount IS NOT NULL
),
TopQuestions AS (
    SELECT *
    FROM RecentActivePosts
    WHERE PostTypeId = 1 AND rn <= 50
),
TopAnswers AS (
    SELECT a.*
    FROM RecentActivePosts a
    INNER JOIN TopQuestions q ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '365 days'
    GROUP BY b.UserId, b.Class
),
UserReputationRank AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC NULLS LAST) AS RepRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
),
TopUsers AS (
    SELECT *
    FROM UserReputationRank
    WHERE RepRank <= 100
),
QuestionCloseDetails AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS CloseDate,
        u.DisplayName AS ClosedByUser,
        ph.Comment
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId AND pht.Name = 'Post Closed'
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS integer) WHERE ph.Comment ~ '^\d+$'
    LEFT JOIN Users u ON u.Id = ph.UserId
    WHERE ph.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
QuestionAnswerScores AS (
    SELECT
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        COUNT(*) AS NumberOfAnswers
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
TopQuestionDetails AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.CreationDate,
        COALESCE(qas.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(qas.MaxAnswerScore, 0) AS MaxAnswerScore,
        COALESCE(qas.NumberOfAnswers, 0) AS NumberOfAnswers,
        q.AcceptedAnswerId,
        cd.CloseReason,
        cd.CloseDate,
        cd.ClosedByUser,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges
    FROM TopQuestions q
    LEFT JOIN QuestionAnswerScores qas ON q.Id = qas.QuestionId
    LEFT JOIN QuestionCloseDetails cd ON q.Id = cd.PostId
    LEFT JOIN TopUsers u ON q.OwnerUserId = u.Id
),
AnswerCommentsInfo AS (
    SELECT
        a.Id AS AnswerId,
        COUNT(c.Id) FILTER (WHERE c.Score > 0) AS PositiveComments,
        COUNT(c.Id) FILTER (WHERE c.Score <= 0 OR c.Score IS NULL) AS NeutralOrNegativeComments,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') FILTER (WHERE c.UserDisplayName IS NOT NULL) AS CommentAuthors
    FROM Posts a
    LEFT JOIN Comments c ON c.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id
),
DetailedAnswerInfo AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        a.Body,
        aci.PositiveComments,
        aci.NeutralOrNegativeComments,
        aci.CommentAuthors,
        COALESCE(u.DisplayName, a.OwnerDisplayName) AS AuthorName,
        COALESCE(u.Reputation, 0) AS AuthorReputation
    FROM TopAnswers a
    LEFT JOIN AnswerCommentsInfo aci ON a.Id = aci.AnswerId
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
),
FinalOutput AS (
    SELECT
        tq.Id AS QuestionId,
        tq.Title,
        REGEXP_REPLACE(tq.Tags, '<|>', ',', 'g') AS ParsedTags,
        tq.QuestionScore,
        tq.ViewCount,
        tq.NumberOfAnswers,
        tq.AvgAnswerScore,
        tq.MaxAnswerScore,
        tq.CloseReason,
        tq.CloseDate,
        tq.ClosedByUser,
        tq.OwnerDisplayName,
        tq.OwnerReputation,
        tq.GoldBadges,
        tq.SilverBadges,
        tq.BronzeBadges,
        da.AnswerId,
        da.Score AS AnswerScore,
        da.PositiveComments,
        da.NeutralOrNegativeComments,
        da.CommentAuthors,
        da.AuthorName AS AnswerAuthor,
        da.AuthorReputation AS AnswerAuthorReputation,
        CASE
            WHEN da.AnswerId = tq.AcceptedAnswerId THEN 'Accepted'
            ELSE 'Not Accepted'
        END AS AnswerStatus,
        LENGTH(REGEXP_REPLACE(da.Body, '<[^>]+>', '', 'g')) AS AnswerBodyLength,
        CASE
            WHEN LENGTH(REGEXP_REPLACE(da.Body, '<[^>]+>', '', 'g')) > 1000 THEN 'Long'
            ELSE 'Short'
        END AS AnswerLengthCategory
    FROM TopQuestionDetails tq
    LEFT JOIN DetailedAnswerInfo da ON tq.Id = da.QuestionId
)
SELECT *
FROM FinalOutput
ORDER BY QuestionScore DESC, ViewCount DESC, NumberOfAnswers DESC, AnswerScore DESC NULLS LAST
LIMIT 100;
