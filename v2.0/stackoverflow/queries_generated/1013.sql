-- {"query": "1013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2263} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User') AS UserDisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserViews,
        u.Location,
        MAX(COALESCE(p.LastActivityDate, u.LastAccessDate)) AS LatestActivityDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score ELSE NULL END) AS AvgPostScore,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.Location
),
PostDetailedMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400 AS PostAgeDays,
        COALESCE(p.LastEditorUserId, -1) AS LastEditor,
        ph_closed.CreationDate AS ClosedDate,
        ph_closed.Comment AS CloseReasonComment,
        ph_reopened.CreationDate AS ReopenedDate,
        LOWER(SPLIT_PART(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '>', 1)) AS FirstTag,
        CASE
            WHEN p.Title LIKE '%SQL%' OR p.Body LIKE '%JOIN%' OR p.Body LIKE '%DATABASE%' THEN TRUE
            ELSE FALSE
        END AS ContainsSqlKeyword,
        COUNT(DISTINCT pl_dup.RelatedPostId) FILTER (WHERE pl_dup.LinkTypeId = 3) AS DuplicateLinksCount,
        COUNT(DISTINCT pl_link.RelatedPostId) FILTER (WHERE pl_link.LinkTypeId = 1) AS LinkedPostsCount
    FROM Posts p
    LEFT JOIN (
        SELECT
            ph_inner.PostId,
            ph_inner.CreationDate,
            ph_inner.Comment,
            ROW_NUMBER() OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate DESC) AS rn
        FROM PostHistory ph_inner
        WHERE ph_inner.PostHistoryTypeId = 10 -- Post Closed
    ) AS ph_closed ON p.Id = ph_closed.PostId AND ph_closed.rn = 1
    LEFT JOIN (
        SELECT
            ph_inner.PostId,
            ph_inner.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate DESC) AS rn
        FROM PostHistory ph_inner
        WHERE ph_inner.PostHistoryTypeId = 11 -- Post Reopened
    ) AS ph_reopened ON p.Id = ph_reopened.PostId AND ph_reopened.rn = 1
    LEFT JOIN PostLinks pl_dup ON p.Id = pl_dup.PostId
    LEFT JOIN PostLinks pl_link ON p.Id = pl_link.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
        p.CommentCount, p.FavoriteCount, p.LastEditorUserId, ph_closed.CreationDate,
        ph_closed.Comment, ph_reopened.CreationDate, p.Title, p.Body, p.Tags
),
HighActivityPosts AS (
    SELECT
        pdm.PostId,
        pdm.PostCreationDate,
        pdm.Score,
        pdm.CommentCount,
        pdm.FavoriteCount
    FROM PostDetailedMetrics pdm
    WHERE pdm.PostTypeId = 1 AND pdm.CommentCount >= 5
    UNION ALL
    SELECT
        pdm.PostId,
        pdm.PostCreationDate,
        pdm.Score,
        pdm.CommentCount,
        pdm.FavoriteCount
    FROM PostDetailedMetrics pdm
    WHERE pdm.PostTypeId = 2 AND pdm.Score >= 10
),
VoteCountsPerPost AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount
    FROM Votes v
    GROUP BY v.PostId
)
SELECT
    u.Id AS UserId,
    ues.UserDisplayName,
    ues.Reputation,
    ues.TotalPosts,
    ues.GoldBadges,
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.CreationDate AS QuestionCreationDate,
    p.Score AS QuestionScore,
    pdm.ViewCount AS QuestionViewCount,
    pdm.PostAgeDays,
    pdm.FirstTag,
    pdm.ContainsSqlKeyword,
    pdm.ClosedDate,
    COALESCE(TRIM(pdm.CloseReasonComment), 'N/A') AS FinalCloseReason,
    ap.Id AS AcceptedAnswerId,
    ap.Score AS AcceptedAnswerScore,
    ap_owner_ues.UserDisplayName AS AcceptedAnswerOwner,
    vcp.UpVoteCount AS QuestionUpVotes,
    vcp.DownVoteCount AS QuestionDownVotes,
    vcp.AcceptedVoteCount AS QuestionAcceptedVotes,
    vcp.FavoriteVoteCount AS QuestionFavoriteVotes,
    ues.LatestActivityDate,
    RANK() OVER (PARTITION BY ues.Location ORDER BY ues.Reputation DESC) AS RankInLocationByReputation,
    AVG(p.Score) OVER (PARTITION BY u.AccountId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RunningAvgPostScoreByAccount,
    (CAST(ues.TotalAnswers AS DECIMAL) / NULLIF(ues.TotalQuestions, 0)) AS AnswerQuestionRatio,
    (SELECT COUNT(DISTINCT b_sub.Name) FROM Badges b_sub WHERE b_sub.UserId = u.Id AND b_sub.Class = 1) AS UserGoldBadgeTypes,
    LOWER(LEFT(u.Location, 5)) AS LocationPrefix,
    EXISTS (SELECT 1 FROM Badges b_spec WHERE b_spec.UserId = u.Id AND b_spec.Name = 'Famous Question' AND b_spec.Date > p.CreationDate) AS HasFamousQuestionBadge,
    hap.CommentCount AS HighInteractionCommentCount,
    hap.FavoriteCount AS HighInteractionFavoriteCount,
    (pdm.DuplicateLinksCount + pdm.LinkedPostsCount) AS TotalRelatedLinks,
    t.TagName AS PrimaryTagName,
    LENGTH(p.Body) AS QuestionBodyLength,
    LENGTH(COALESCE(ap.Body, '')) AS AcceptedAnswerBodyLength
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserEngagementSummary ues ON u.Id = ues.UserId
LEFT JOIN PostDetailedMetrics pdm ON p.Id = pdm.PostId
LEFT JOIN Posts ap ON p.AcceptedAnswerId = ap.Id
LEFT JOIN UserEngagementSummary ap_owner_ues ON ap.OwnerUserId = ap_owner_ues.UserId
LEFT JOIN VoteCountsPerPost vcp ON p.Id = vcp.PostId
LEFT JOIN HighActivityPosts hap ON p.Id = hap.PostId
LEFT JOIN Tags t ON pdm.FirstTag = LOWER(t.TagName)
WHERE
    p.PostTypeId = 1
    AND p.CreationDate >= (NOW() - INTERVAL '5 years')
    AND (p.Score > 10 OR pdm.ViewCount > 5000 OR ues.Reputation > 10000)
    AND pdm.ClosedDate IS NULL
    AND u.Location IS NOT NULL AND u.Location <> ''
    AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50
    AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name = 'Announcer')
    AND (p.LastEditorUserId IS NULL OR p.LastEditDate >= (NOW() - INTERVAL '6 months')) -- Check for recently edited or unedited posts
ORDER BY
    ues.Reputation DESC,
    QuestionScore DESC,
    pdm.PostAgeDays ASC
LIMIT 10000;
