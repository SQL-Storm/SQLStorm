-- {"query": "5042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1051} 
WITH RecentEdits AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorUserId,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title/Body/Tags
),
LatestPostEdit AS (
    SELECT 
        re.PostId,
        re.EditDate,
        re.EditorUserId,
        re.PostHistoryTypeId
    FROM RecentEdits re
    WHERE re.rn = 1
),
UserBadgeRank AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionScoreAnalytics AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS AvgAnswerScore,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score
    HAVING COUNT(a.Id) >= 2
),
DupLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate AS LinkDate,
        lt.Name AS LinkType
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.LinkTypeId = 3
),
ClosedWithReason AS (
    SELECT
        ph.PostId,
        cr.Name AS CloseReason,
        ph.CreationDate AS ClosedDate
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes cr ON cr.Id::varchar = ph.Comment
    WHERE ph.PostHistoryTypeId = 10
),
HighCommentPosts AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anon'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
    HAVING COUNT(c.Id) >= 5
)
SELECT
    q.QuestionId,
    q.Title,
    u.DisplayName AS QuestionOwner,
    u.Reputation AS OwnerReputation,
    u.ReputationRank AS OwnerReputationRank,
    q.QuestionScore,
    q.AvgAnswerScore,
    q.MaxAnswerScore,
    q.AnswerCount,
    (q.QuestionScore * COALESCE(q.AvgAnswerScore, 0)) AS ScoreProduct,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    CASE 
        WHEN cw.CloseReason IS NOT NULL THEN cw.CloseReason 
        ELSE 'Open' 
    END AS CloseReason,
    le.EditDate AS LastEditDate,
    eu.DisplayName AS LastEditor,
    hc.CommentCount AS HighCommentCount,
    hc.Commenters AS FrequentCommenters,
    dl.RelatedPostId AS DuplicatedWith,
    SUBSTRING(q.Title, 1, 50) || 
        CASE WHEN LENGTH(q.Title) > 50 THEN '...' ELSE '' END AS ShortTitle
FROM QuestionScoreAnalytics q
LEFT JOIN UserBadgeRank u ON q.OwnerUserId = u.UserId
LEFT JOIN UserBadgeRank b ON q.OwnerUserId = b.UserId
LEFT JOIN ClosedWithReason cw ON q.QuestionId = cw.PostId
LEFT JOIN LatestPostEdit le ON le.PostId = q.QuestionId
LEFT JOIN Users eu ON le.EditorUserId = eu.Id
LEFT JOIN HighCommentPosts hc ON q.QuestionId = hc.PostId
LEFT JOIN DupLinks dl ON q.QuestionId = dl.PostId
WHERE (q.QuestionScore + COALESCE(q.AvgAnswerScore, 0) * 2) > 10
  AND (cw.CloseReason IS NULL OR cw.CloseReason NOT IN ('Duplicate','Off-topic'))
  AND (b.GoldBadges > 0 OR b.SilverBadges > 1)
ORDER BY 
    q.QuestionScore DESC,
    COALESCE(q.AvgAnswerScore, 0) DESC,
    u.ReputationRank ASC
LIMIT 100;