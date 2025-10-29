WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalQuestionsPosted,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationTier,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS LastEditActivityDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.UpVotes, u.DownVotes, u.Views
),
QuestionEventMetrics AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVoteCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
        STRING_AGG(DISTINCT crt.Name, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND crt.Id = CAST(ph.Comment AS INTEGER)) AS CloseReasons
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND crt.Id = CAST(ph.Comment AS INTEGER)
    GROUP BY ph.PostId
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><'), 1) AS TagCount,
        EXISTS (
            SELECT 1
            FROM unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS tag
            WHERE tag IN ('sql', 'database', 'performance', 'query-optimization')
        ) AS HasRelevantTag,
        STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IN ('sql', 'database', 'performance', 'query-optimization')) AS RelevantTags
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS tag_unnest(tag) ON TRUE
    LEFT JOIN Tags t ON t.TagName = tag_unnest.tag
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
    GROUP BY p.Id, p.Tags
),
CommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN lower(c.Text) LIKE '%great%' OR lower(c.Text) LIKE '%thanks%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN lower(c.Text) LIKE '%bug%' OR lower(c.Text) LIKE '%error%' OR lower(c.Text) LIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    ue.UserName,
    ue.Reputation,
    ue.ReputationTier,
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate AS QuestionCreationDate,
    p.LastActivityDate,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    COALESCE(p.LastEditorDisplayName, (SELECT u_edit.DisplayName FROM Users u_edit WHERE u_edit.Id = p.LastEditorUserId), 'Community Editor') AS EffectiveLastEditor,
    pta.TagCount,
    pta.RelevantTags,
    pta.HasRelevantTag,
    COALESCE(cs.CommentCount, 0) AS TotalCommentsOnQuestion,
    COALESCE(cs.AvgCommentScore, 0.0) AS AverageCommentScore,
    COALESCE(cs.PositiveCommentCount, 0) AS PositiveFeedbackComments,
    COALESCE(cs.NegativeCommentCount, 0) AS NegativeFeedbackComments,
    COALESCE(cs.LastCommentDate, p.LastActivityDate, p.CreationDate) AS EffectiveLastActivity,
    qem.EditCount,
    qem.CloseVoteCount,
    qem.LastClosedDate,
    qem.CloseReasons,
    pl_linked.RelatedPostId AS LinkedQuestionId,
    pl_dup.RelatedPostId AS DuplicateOfQuestionId,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
        WHEN p.AnswerCount > 0 THEN 'Answered'
        ELSE 'Unanswered'
    END AS QuestionStatus,
    p.CreationDate - COALESCE(LAG(p.CreationDate) OVER (PARTITION BY ue.UserId ORDER BY p.CreationDate), TIMESTAMP '1900-01-01') AS TimeSincePreviousQuestion,
    (p.Score * 0.6 + p.ViewCount * 0.01 + COALESCE(p.FavoriteCount, 0) * 0.3 + COALESCE(cs.CommentCount, 0) * 0.1) *
    (CASE WHEN pta.HasRelevantTag THEN 1.2 ELSE 0.8 END) AS EngagementScore,
    RANK() OVER (PARTITION BY ue.ReputationTier ORDER BY p.ViewCount DESC, p.Score DESC) AS RankWithinReputationTier,
    AVG(p.Score) OVER (PARTITION BY CAST(p.CreationDate AS DATE)) AS DailyAverageQuestionScore,
    EXISTS (
        SELECT 1
        FROM PostHistory ph_owner_edit
        WHERE ph_owner_edit.PostId = p.Id
          AND ph_owner_edit.UserId = ue.UserId
          AND ph_owner_edit.PostHistoryTypeId IN (4, 5, 6)
          AND ph_owner_edit.CreationDate BETWEEN p.CreationDate AND COALESCE(p.LastEditDate, p.CreationDate)
    ) AS OwnerHasEditedQuestion,
    (SELECT MAX(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS BestAnswerScore,
    (p.ClosedDate IS NOT NULL AND p.ViewCount > 5000 AND p.Score < 0 AND COALESCE(qem.CloseVoteCount, 0) > 1) AS HighlyViewedButClosedNegative
FROM Posts p
INNER JOIN UserEngagement ue ON p.OwnerUserId = ue.UserId
INNER JOIN PostTagAnalysis pta ON p.Id = pta.PostId
LEFT JOIN QuestionEventMetrics qem ON p.Id = qem.PostId
LEFT JOIN CommentSentiment cs ON p.Id = cs.PostId
LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
LEFT JOIN PostLinks pl_dup ON p.Id = pl_dup.PostId AND pl_dup.LinkTypeId = 3
WHERE
    p.PostTypeId = 1
    AND p.CreationDate BETWEEN TIMESTAMP '2022-01-01' AND TIMESTAMP '2023-12-31'
    AND p.ViewCount > 1000
    AND p.Score >= 0
    AND ue.Reputation > 1000
    AND pta.HasRelevantTag IS TRUE
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks pl_is_dup
        WHERE pl_is_dup.PostId = p.Id AND pl_is_dup.LinkTypeId = 3
    )
    AND (
        (COALESCE(p.FavoriteCount, 0) > 5 AND p.LastActivityDate > p.CreationDate + INTERVAL '3 months')
        OR (p.AnswerCount IS NOT NULL AND p.AnswerCount > 2 AND p.AcceptedAnswerId IS NOT NULL AND lower(p.Body) LIKE '%solution%')
        OR (COALESCE(cs.CommentCount, 0) > 10 AND COALESCE(cs.AvgCommentScore, 0) >= 1 AND COALESCE(cs.NegativeCommentCount, 0) = 0)
    )
ORDER BY
    EngagementScore DESC, p.CreationDate DESC, p.ViewCount DESC
LIMIT 1000;