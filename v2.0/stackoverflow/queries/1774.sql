WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId IN ((SELECT Id FROM PostTypes WHERE Name = 'Question'), (SELECT Id FROM PostTypes WHERE Name = 'Answer')) THEN p.Score END), 0.0) AS AvgActivePostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS ReceivedUpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS ReceivedDownVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostRevisionMetrics AS (
    SELECT
        ph.PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.ClosedDate,
        p.AcceptedAnswerId,
        SUM(CASE WHEN pht.Name LIKE '%Body%' THEN 1 ELSE 0 END) AS BodyEditCount,
        SUM(CASE WHEN pht.Name LIKE '%Tags%' THEN 1 ELSE 0 END) AS TagEditCount,
        SUM(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN pht.Name = 'Post Reopened' THEN 1 ELSE 0 END) AS ReopenEventCount,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        MAX(ph.CreationDate) AS LastHistoryDate,
        STRING_AGG(CASE WHEN pht.Name = 'Post Closed' AND ph.Comment IS NOT NULL THEN crt.Name END, '; ') AS CloseReasonNames,
        MAX(CASE WHEN pht.Name = 'Post Closed' THEN ph.CreationDate END) AS LatestCloseDate,
        MAX(CASE WHEN pht.Name = 'Post Reopened' THEN ph.CreationDate END) AS LatestReopenDate
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') AND ph.Comment = CAST(crt.Id AS VARCHAR)
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
    GROUP BY ph.PostId, p.PostTypeId, p.CreationDate, p.LastEditDate, p.ClosedDate, p.AcceptedAnswerId
),
BadgeAchievementSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        SUM(CASE WHEN b.TagBased = FALSE THEN 1 ELSE 0 END) AS NamedBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2020-01-01 00:00:00'
    GROUP BY b.UserId
),
ComplexPostFeatures AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score AS PostScore,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p_aa.Score AS AcceptedAnswerScore,
        p_aa.OwnerUserId AS AcceptedAnswerOwnerUserId,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.AcceptedAnswerId AND c.UserId IS NOT NULL) AS AcceptedAnswerCommentCount,
        p.Tags,
        p.AnswerCount,
        p.CommentCount AS QuestionCommentCount,
        pl.RelatedPostId AS DuplicateOfPostId,
        (CASE WHEN p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' OR p.Tags LIKE '%<nosql>%' THEN 1 ELSE 0 END) AS IsDatabaseRelated,
        (CASE WHEN p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<optimization>%' OR p.Tags LIKE '%<scalability>%' THEN 1 ELSE 0 END) AS IsPerformanceRelated,
        (p.ContentLicense = 'CC BY-SA 4.0') AS IsRecentContentLicense
    FROM Posts p
    LEFT JOIN Posts p_aa ON p.AcceptedAnswerId = p_aa.Id
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
    WHERE p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
      AND p.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
),
AggregatedPostData AS (
    SELECT
        cpf.PostId,
        cpf.Title,
        cpf.PostScore,
        cpf.ViewCount,
        cpf.OwnerUserId,
        cpf.AcceptedAnswerId,
        cpf.AcceptedAnswerScore,
        cpf.AcceptedAnswerOwnerUserId,
        cpf.AcceptedAnswerCommentCount,
        cpf.Tags,
        cpf.IsDatabaseRelated,
        cpf.IsPerformanceRelated,
        cpf.IsRecentContentLicense,
        prm.PostCreationDate,
        prm.LastEditDate,
        prm.ClosedDate,
        prm.BodyEditCount,
        prm.TagEditCount,
        prm.CloseEventCount,
        prm.ReopenEventCount,
        prm.LatestCloseDate,
        prm.LatestReopenDate,
        prm.CloseReasonNames,
        CASE
            WHEN prm.PostCreationDate IS NULL OR prm.LastEditDate IS NULL THEN 0
            ELSE CAST(EXTRACT(EPOCH FROM (prm.LastEditDate - prm.PostCreationDate)) / 86400 AS INTEGER)
        END AS DaysSinceCreationToLastEdit,
        (CASE
            WHEN prm.CloseEventCount > 0 AND prm.ReopenEventCount > 0 AND prm.LatestReopenDate > prm.LatestCloseDate
            THEN 'Reopened_and_Active'
            WHEN prm.CloseEventCount > 0
            THEN 'Closed_Permanently'
            ELSE 'Open_or_Never_Closed'
        END) AS PostStatusCategory,
        (COALESCE(LENGTH(cpf.Body), 0) > 1000 AND (cpf.Body LIKE '%<code>%' OR cpf.Body LIKE '%<pre>%')) AS HasExtensiveCodeBlock
    FROM ComplexPostFeatures cpf
    INNER JOIN PostRevisionMetrics prm ON cpf.PostId = prm.PostId
    WHERE (cpf.AcceptedAnswerId IS NOT NULL OR prm.CloseEventCount > 0)
      AND cpf.IsDatabaseRelated = 1
      AND (prm.BodyEditCount > 2 OR prm.TagEditCount > 1)
      AND prm.PostCreationDate >= TIMESTAMP '2020-01-01 00:00:00'
      AND prm.PostCreationDate <= TIMESTAMP '2023-12-31 23:59:59'
),
FinalUserActivityRank AS (
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.TotalQuestions,
        ues.TotalAnswers,
        ues.TotalPosts,
        ues.TotalComments,
        COALESCE(bas.GoldBadges, 0) AS GoldBadges,
        COALESCE(bas.SilverBadges, 0) AS SilverBadges,
        COALESCE(bas.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bas.TagBasedBadges, 0) AS TagBasedBadges,
        COALESCE(bas.NamedBadges, 0) AS NamedBadges,
        (ues.Reputation * 0.15) + (ues.AvgActivePostScore * 0.4) + (ues.AvgCommentScore * 0.1) + (COALESCE(bas.GoldBadges, 0) * 12) + (COALESCE(bas.SilverBadges, 0) * 6) + (COALESCE(bas.TagBasedBadges, 0) * 2) AS WeightedUserScore,
        DENSE_RANK() OVER (ORDER BY
            (ues.Reputation * 0.15) + (ues.AvgActivePostScore * 0.4) + (ues.AvgCommentScore * 0.1) + (COALESCE(bas.GoldBadges, 0) * 12) + (COALESCE(bas.SilverBadges, 0) * 6) + (COALESCE(bas.TagBasedBadges, 0) * 2) DESC,
            ues.DisplayName ASC
        ) AS UserRank,
        NTILE(10) OVER (ORDER BY ues.Reputation DESC) AS ReputationDecile
    FROM UserEngagementSummary ues
    LEFT JOIN BadgeAchievementSummary bas ON ues.UserId = bas.UserId
    WHERE ues.TotalPosts > 5 AND ues.Reputation > 1000
      AND EXISTS (
        SELECT 1
        FROM Posts p_exists
        WHERE p_exists.OwnerUserId = ues.UserId
          AND p_exists.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
          AND p_exists.ViewCount > 7500
          AND p_exists.FavoriteCount IS NOT NULL
          AND p_exists.FavoriteCount >= 20
          AND p_exists.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
          AND p_exists.ClosedDate IS NULL
    )
    AND (
        (ues.DisplayName IS NOT NULL AND LENGTH(TRIM(ues.DisplayName)) > 0)
        OR EXISTS (
            SELECT 1 FROM Users u WHERE u.Id = ues.UserId AND u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 50
        )
    )
)
SELECT
    fuar.UserRank,
    fuar.ReputationDecile,
    fuar.DisplayName,
    fuar.Reputation,
    fuar.WeightedUserScore,
    fuar.TotalQuestions,
    fuar.TotalAnswers,
    fuar.TotalComments,
    fuar.GoldBadges,
    fuar.SilverBadges,
    fuar.TagBasedBadges,
    apd.PostId,
    apd.Title AS RelevantPostTitle,
    apd.PostScore AS RelevantPostScore,
    apd.ViewCount AS RelevantPostViewCount,
    apd.AcceptedAnswerScore,
    apd.AcceptedAnswerCommentCount,
    apd.Tags AS RelevantPostTags,
    apd.PostStatusCategory,
    apd.BodyEditCount,
    apd.TagEditCount,
    apd.CloseEventCount,
    apd.ReopenEventCount,
    apd.DaysSinceCreationToLastEdit,
    apd.PostCreationDate,
    apd.LastEditDate,
    apd.LatestCloseDate,
    apd.LatestReopenDate,
    apd.CloseReasonNames,
    apd.IsPerformanceRelated,
    apd.HasExtensiveCodeBlock,
    apd.IsRecentContentLicense,
    AVG(CASE WHEN apd_other.PostId IS NOT NULL AND apd.PostId <> apd_other.PostId THEN apd_other.PostScore ELSE NULL END)
        OVER (PARTITION BY fuar.UserId ORDER BY apd.PostId) AS AvgScoreOfUsersOtherRelevantPosts,
    UPPER(SUBSTRING(fuar.DisplayName FROM 1 FOR 3)) || '...' || LOWER(REVERSE(SUBSTRING(REVERSE(fuar.DisplayName) FROM 1 FOR 3))) AS DisplayNameTeaser,
    COALESCE(
        (CAST(fuar.TotalQuestions AS NUMERIC) / NULLIF(fuar.TotalPosts, 0) * 50),
        0
    ) + COALESCE(
        (CAST(fuar.GoldBadges AS NUMERIC) / NULLIF(COALESCE(bas_total.TotalBadges, 0), 0) * 25),
        0
    ) + COALESCE(
        (CAST(apd.AcceptedAnswerCommentCount AS NUMERIC) / NULLIF(COALESCE(apd.AcceptedAnswerScore, 0) + 1, 0) * 10),
        0
    ) AS CombinedEngagementScore
FROM FinalUserActivityRank fuar
LEFT JOIN AggregatedPostData apd ON fuar.UserId = apd.OwnerUserId
LEFT JOIN AggregatedPostData apd_other ON fuar.UserId = apd_other.OwnerUserId
LEFT JOIN BadgeAchievementSummary bas_total ON fuar.UserId = bas_total.UserId
WHERE fuar.UserRank <= 100
  AND (apd.PostId IS NOT NULL OR fuar.TotalQuestions >= 15)
  AND (apd.IsPerformanceRelated = 1 OR apd.PostScore > 50)
  AND (
        apd.ClosedDate IS NOT NULL
        OR (apd.LastEditDate IS NOT NULL AND CAST(EXTRACT(EPOCH FROM (apd.LastEditDate - apd.PostCreationDate)) / 3600 AS INTEGER) > 24)
      )
ORDER BY fuar.UserRank ASC, apd.PostScore DESC NULLS LAST, apd.ViewCount DESC;