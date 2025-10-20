WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(100)) AS Path
    FROM Tags t
    WHERE t.IsRequired = TRUE

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1 AS Level,
        CAST(r.Path || ' > ' || child.TagName AS VARCHAR(100)) AS Path
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy r ON child.Id <> r.Id
        AND child.IsRequired = TRUE
        AND child.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score = 0 THEN 'Neutral'
            ELSE 'Negative'
        END AS ScoreCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostCloseReasonCounts AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment ~ '^\d+$'
    GROUP BY ph.PostId, crt.Name
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommented,
        COUNT(*) AS TotalComments,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT SUBSTRING(c.Text FROM 1 FOR 30), ' | ') AS SampleComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
AnswerWithAcceptedFlag AS (
    SELECT
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        q.Title AS QuestionTitle,
        q.Tags AS QuestionTags
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        SUM(a.IsAccepted) AS AcceptedAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT tag) AS DistinctTagsAnswered
    FROM (
        SELECT
            OwnerUserId,
            IsAccepted,
            Score,
            UNNEST(STRING_TO_ARRAY(SUBSTRING(QuestionTags FROM 2 FOR CHAR_LENGTH(QuestionTags)-2), '><')) AS tag
        FROM AnswerWithAcceptedFlag
    ) a
    GROUP BY a.OwnerUserId
),
CombinedUserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.TagBasedBadges, 0) AS TagBasedBadges,
        COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(uas.AcceptedAnswers, 0) AS AcceptedAnswers,
        COALESCE(uas.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(uas.DistinctTagsAnswered, 0) AS DistinctTagsAnswered,
        COALESCE(uca.DistinctPostsCommented, 0) AS DistinctPostsCommented,
        COALESCE(uca.TotalComments, 0) AS TotalComments,
        uca.LastCommentDate,
        ubs.LastBadgeDate
    FROM Users u
    LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = u.Id
    LEFT JOIN UserAnswerStats uas ON uas.OwnerUserId = u.Id
    LEFT JOIN UserCommentActivity uca ON uca.UserId = u.Id
)
SELECT
    cus.Id AS UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.CreationDate,
    cus.LastAccessDate,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.TagBasedBadges,
    cus.TotalAnswers,
    cus.AcceptedAnswers,
    ROUND(CAST(cus.AvgAnswerScore AS NUMERIC), 2) AS AvgAnswerScore,
    cus.DistinctTagsAnswered,
    cus.DistinctPostsCommented,
    cus.TotalComments,
    cus.LastCommentDate,
    cus.LastBadgeDate,
    rth.Level AS TagHierarchyLevel,
    rth.Path AS TagHierarchyPath,
    COALESCE(pcrc.CloseCount, 0) AS TotalCloseVotes,
    COALESCE(pcrc.CloseReasonName, 'No Close Reason') AS MostCommonCloseReason,
    CASE
        WHEN cus.Reputation > 10000 THEN 'High Rep'
        WHEN cus.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS ReputationCategory,
    CASE
        WHEN cus.TotalAnswers > 0 THEN ROUND((CAST(cus.AcceptedAnswers AS NUMERIC) / cus.TotalAnswers) * 100, 2)
        ELSE NULL
    END AS AcceptedAnswerPercentage,
    CASE
        WHEN cus.TotalComments > 0 THEN ROUND((CAST(cus.DistinctPostsCommented AS NUMERIC) / cus.TotalComments) * 100, 2)
        ELSE NULL
    END AS CommentSpreadPercentage,
    CONCAT_WS(' | ',
        SUBSTRING(cus.DisplayName FROM 1 FOR 10),
        'Rep: ' || cus.Reputation,
        'Badges: G' || cus.GoldBadges || ' S' || cus.SilverBadges || ' B' || cus.BronzeBadges,
        'Answers: ' || cus.TotalAnswers,
        'Accepted %: ' || COALESCE(CAST(ROUND((CAST(cus.AcceptedAnswers AS NUMERIC) / NULLIF(cus.TotalAnswers,0)) * 100,2) AS TEXT), 'N/A'),
        'Comments: ' || cus.TotalComments
    ) AS UserSummary
FROM CombinedUserStats cus
LEFT JOIN RecursiveTagHierarchy rth ON rth.Level = 1
LEFT JOIN (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        SUM(1) AS CloseCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment ~ '^\d+$'
    GROUP BY ph.PostId, crt.Name
    ORDER BY CloseCount DESC
    LIMIT 1
) pcrc ON pcrc.PostId = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = cus.Id ORDER BY p.ViewCount DESC LIMIT 1
)
WHERE cus.Reputation > 500
ORDER BY cus.Reputation DESC, cus.TotalAnswers DESC
LIMIT 50;