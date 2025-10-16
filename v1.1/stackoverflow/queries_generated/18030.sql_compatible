WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        COUNT(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 END) AS AcceptedAnswerExists
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserPostContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.PostId END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN ph.PostId END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN ph.PostId END) AS TagEdits,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS QuestionsPosted,
        COUNT(a.Id) AS AnswersPosted,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavorites,
        MAX(u.Reputation) AS MaxUserReputation,
        AVG(u.Reputation) AS AvgUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
)
SELECT
    rq.QuestionId,
    rq.Title AS QuestionTitle,
    u.DisplayName AS QuestionOwnerDisplayName,
    rq.QuestionScore,
    rq.AnswerCount,
    COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ans.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ans.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(ans.MaxAnswerScore, 0) AS MaxAnswerScore,
    CASE WHEN COALESCE(ans.AcceptedAnswerExists, 0) > 0 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    upc.BodyEdits,
    upc.TitleEdits,
    upc.TagEdits,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalQuestionViews,
    ua.TotalFavorites,
    u.Reputation AS OwnerReputation,
    u.Views AS OwnerViews,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes,
    u.CreationDate AS OwnerCreationDate,
    CAST(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) AS INTEGER) AS OwnerAccountAgeDays,
    CASE
        WHEN u.Location IS NULL THEN 'Unknown'
        WHEN POSITION('united states' IN LOWER(u.Location)) > 0 THEN 'USA'
        WHEN POSITION('canada' IN LOWER(u.Location)) > 0 THEN 'Canada'
        WHEN POSITION('united kingdom' IN LOWER(u.Location)) > 0 THEN 'UK'
        ELSE 'Other'
    END AS OwnerCountry,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT SUM(c.Score) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')) AS LastYearCommentScore,
    (
        SELECT pht.Name
        FROM PostHistoryTypes pht
        WHERE pht.Id = (
            SELECT MIN(ph2.PostHistoryTypeId)
            FROM PostHistory ph2
            WHERE ph2.PostId = rq.QuestionId
              AND ph2.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
        )
        LIMIT 1
    ) AS FirstModerationAction,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3
    ) AS DuplicateLinksCount
FROM RankedQuestions rq
JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN AnswerStats ans ON rq.QuestionId = ans.QuestionId
LEFT JOIN UserPostContribution upc ON rq.OwnerUserId = upc.UserId
LEFT JOIN UserActivity ua ON rq.OwnerUserId = ua.UserId
WHERE rq.rn <= 1000
ORDER BY rq.QuestionCreationDate DESC;