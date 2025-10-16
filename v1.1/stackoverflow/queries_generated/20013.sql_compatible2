WITH UserPostMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.AboutMe,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0.0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0.0) AS AvgAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoriteCount,
        SUM(COALESCE(p.CommentCount,0)) AS TotalPostCommentCount,
        COUNT(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS QuestionsWithAcceptedAnswers
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Id > 0
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.AboutMe
),
UserBadgeMetrics AS (
    SELECT
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        SUM(CASE Class WHEN 1 THEN 100 WHEN 2 THEN 25 WHEN 3 THEN 5 ELSE 0 END) AS BadgeScore
    FROM
        Badges
    GROUP BY
        UserId
),
UserInteractionMetrics AS (
    SELECT
        UserId,
        COUNT(*) AS TotalVotesCast,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesCast,
        SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM
        Votes
    WHERE
        UserId IS NOT NULL
    GROUP BY
        UserId
),
AggregatedUserData AS (
    SELECT
        upm.UserId,
        upm.DisplayName,
        upm.Reputation,
        EXTRACT(YEAR FROM upm.CreationDate) AS CreationYear,
        COALESCE(ubm.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubm.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubm.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubm.BadgeScore, 0) AS BadgeScore,
        upm.QuestionCount,
        upm.AnswerCount,
        upm.TotalQuestionScore,
        upm.TotalAnswerScore,
        upm.AvgQuestionScore,
        upm.AvgAnswerScore,
        upm.TotalViewCount,
        COALESCE(uim.UpVotesCast, 0) AS UpVotesCast,
        COALESCE(uim.DownVotesCast, 0) AS DownVotesCast,
        upm.TotalPostCommentCount,
        (upm.Reputation / 100.0) * LN(1 + upm.QuestionCount + upm.AnswerCount) + COALESCE(ubm.BadgeScore, 0) * 1.5 AS EngagementScore,
        (SELECT p.Title FROM Posts p WHERE p.OwnerUserId = upm.UserId AND p.PostTypeId = 1 ORDER BY p.Score DESC, p.CreationDate DESC LIMIT 1) AS BestQuestionTitle,
        EXISTS (SELECT 1 FROM Posts p WHERE p.LastEditorUserId = upm.UserId AND p.OwnerUserId <> upm.UserId) AS HasEditedOthersPosts
    FROM
        UserPostMetrics upm
    LEFT JOIN
        UserBadgeMetrics ubm ON upm.UserId = ubm.UserId
    LEFT JOIN
        UserInteractionMetrics uim ON upm.UserId = uim.UserId
    WHERE
        upm.Reputation > (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY Reputation) FROM Users)
        AND upm.QuestionCount > 10
        AND upm.AnswerCount > 20
        AND COALESCE(ubm.GoldBadges, 0) > 0
)
SELECT
    'Power User' AS UserType,
    UserId,
    DisplayName,
    Reputation,
    CreationYear,
    GoldBadges,
    QuestionCount,
    AnswerCount,
    TotalQuestionScore / NULLIF(QuestionCount, 0) AS NormQuestionScore,
    TotalAnswerScore / NULLIF(AnswerCount, 0) AS NormAnswerScore,
    UPPER(SUBSTRING(BestQuestionTitle FROM 1 FOR 50)) || '...' AS TruncatedBestTitle,
    EngagementScore,
    RANK() OVER (PARTITION BY CreationYear ORDER BY Reputation DESC) AS RankInYear,
    NTILE(100) OVER (ORDER BY EngagementScore DESC) AS EngagementPercentile,
    (Reputation - LAG(Reputation, 1, Reputation) OVER (ORDER BY Reputation DESC)) / NULLIF(Reputation, 0) AS RepDiffRatioWithPrevious
FROM
    AggregatedUserData
WHERE
    EngagementScore > 500 AND BestQuestionTitle IS NOT NULL AND HasEditedOthersPosts

UNION ALL

SELECT
    'Controversial User' AS UserType,
    u.Id,
    u.DisplayName,
    u.Reputation,
    EXTRACT(YEAR FROM u.CreationDate),
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1),
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2),
    NULL AS NormQuestionScore,
    NULL AS NormAnswerScore,
    (SELECT
        STRING_AGG(CASE crt.Id
            WHEN 101 THEN 'Dup'
            WHEN 102 THEN 'Off-T'
            WHEN 103 THEN 'Clarity'
            WHEN 104 THEN 'Focus'
            ELSE 'Other'
        END, ', ')
     FROM PostHistory ph
     JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
     WHERE ph.PostHistoryTypeId = 10 AND ph.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id)
    ) AS TruncatedBestTitle,
    (u.DownVotes * 1.0 * 100) / NULLIF(u.UpVotes, 0) AS EngagementScore,
    NULL AS RankInYear,
    NULL AS EngagementPercentile,
    NULL AS RepDiffRatioWithPrevious
FROM
    Users u
WHERE
    u.DownVotes > u.UpVotes / 4 AND u.Reputation > 10000 AND u.UpVotes > 100
    AND u.Id IN (
        SELECT v.UserId
        FROM Votes v
        WHERE v.VoteTypeId = 3
        GROUP BY v.UserId
        HAVING COUNT(*) > 50
    )
ORDER BY
    UserType, Reputation DESC
LIMIT 500;