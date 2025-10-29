-- {"query": "4405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1498} 
WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.Score) AS MaxScore,
        MIN(p.Score) AS MinScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(p.AnswerCount) AS AverageAnswerCountPerQuestion,
        COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS ClosedPostCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentCount
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY c.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadgeCount,
        COUNT(CASE WHEN b.TagBased = 1 THEN b.Id ELSE NULL END) AS TagBadges,
        COUNT(CASE WHEN b.TagBased = 0 THEN b.Id ELSE NULL END) AS NamedBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentPostHistory AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
),
LatestEdits AS (
    SELECT
        rph.UserId AS EditorUserId,
        rph.PostId,
        rph.CreationDate AS EditDate,
        CASE
            WHEN rph.PostHistoryTypeId = 4 THEN 'Title'
            WHEN rph.PostHistoryTypeId = 5 THEN 'Body'
            WHEN rph.PostHistoryTypeId = 6 THEN 'Tags'
            ELSE 'Unknown'
        END AS EditType
    FROM RecentPostHistory rph
    WHERE rph.rn = 1
),
UserReputationChange AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        LAG(u.Reputation, 1, u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate) AS PreviousReputation,
        u.CreationDate,
        u.LastAccessDate
    FROM Users u
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    CASE
        WHEN urc.Reputation > urc.PreviousReputation THEN 'Increased'
        WHEN urc.Reputation < urc.PreviousReputation THEN 'Decreased'
        ELSE 'No Change'
    END AS ReputationChangeStatus,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.QuestionCount, 0) AS QuestionCount,
    COALESCE(ups.AnswerCount, 0) AS AnswerCount,
    ups.AverageScore,
    ups.MaxScore,
    ups.MinScore,
    COALESCE(ups.AcceptedAnswers, 0) AS AcceptedAnswers,
    ups.AverageAnswerCountPerQuestion,
    COALESCE(ups.ClosedPostCount, 0) AS ClosedPostCount,
    COALESCE(ucs.TotalComments, 0) AS TotalComments,
    ucs.AverageCommentScore,
    COALESCE(ucs.PositiveCommentCount, 0) AS PositiveCommentCount,
    COALESCE(ucs.NegativeCommentCount, 0) AS NegativeCommentCount,
    COALESCE(ubs.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(ubs.SilverBadgeCount, 0) AS SilverBadgeCount,
    COALESCE(ubs.BronzeBadgeCount, 0) AS BronzeBadgeCount,
    COALESCE(ubs.TagBadges, 0) AS TagBadges,
    COALESCE(ubs.NamedBadges, 0) AS NamedBadges,
    le.EditorUserId AS LastEditorId,
    le.EditDate AS LastEditDate,
    le.EditType AS LastEditType,
    CASE
        WHEN u.WebsiteUrl IS NULL THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow%' THEN 'Stack Overflow Related Website'
        ELSE 'External Website'
    END AS WebsiteCategory,
    u.Views,
    UPPER(SUBSTRING(COALESCE(u.AboutMe, 'No Description') FROM 1 FOR 10)) AS AboutMeFirstChars,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Guru%') THEN 'Guru Badge Holder'
        ELSE 'No Guru Badge'
    END AS GuruStatus,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = u.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN LatestEdits le ON u.Id = le.PostId
LEFT JOIN UserReputationChange urc ON u.Id = urc.UserId
WHERE u.Id < 100000
ORDER BY u.Reputation DESC, u.CreationDate ASC
LIMIT 50;