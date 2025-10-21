WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
TopAnswerers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS AcceptedAnswers,
        AVG(p.Score) AS AvgAcceptedScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS AcceptedRank
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 
        AND q.AcceptedAnswerId = p.Id
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        CAST(regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS TEXT) AS TagName,
        COUNT(*) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TagAnswerCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, TagName
    HAVING COUNT(*) >= 10
),
VotingPatterns AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast,
        COUNT(DISTINCT DATE(v.CreationDate)) AS ActiveVotingDays
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2020-01-01'
        AND v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.PostId) AS PostsCommentedOn
    FROM Comments c
    WHERE c.UserId IS NOT NULL
        AND c.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY c.UserId
),
EditHistory AS (
    SELECT 
        ph.UserId,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.CreationDate >= TIMESTAMP '2020-01-01'
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.UserId
)
SELECT 
    uem.UserId,
    uem.DisplayName,
    uem.Reputation,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - uem.UserCreationDate)) AS AccountAgeDays,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    ROUND(uem.AvgPostScore, 2) AS AvgPostScore,
    uem.TotalViews,
    uem.BadgeCount,
    uem.GoldBadges,
    uem.SilverBadges,
    uem.BronzeBadges,
    COALESCE(ta.AcceptedAnswers, 0) AS AcceptedAnswers,
    COALESCE(ROUND(ta.AvgAcceptedScore, 2), 0) AS AvgAcceptedScore,
    COALESCE(ta.AcceptedRank, 9999) AS AcceptedRank,
    COALESCE(te.TopTagName, 'N/A') AS TopTagName,
    COALESCE(te.TopTagPostCount, 0) AS TopTagPostCount,
    COALESCE(ROUND(te.TopTagScore, 2), 0) AS TopTagScore,
    COALESCE(vp.UpvotesCast, 0) AS UpvotesCast,
    COALESCE(vp.DownvotesCast, 0) AS DownvotesCast,
    COALESCE(vp.FavoritesCast, 0) AS FavoritesCast,
    COALESCE(vp.ActiveVotingDays, 0) AS ActiveVotingDays,
    COALESCE(ca.CommentCount, 0) AS CommentCount,
    COALESCE(ROUND(ca.AvgCommentScore, 2), 0) AS AvgCommentScore,
    COALESCE(eh.EditCount, 0) AS EditCount,
    COALESCE(eh.PostsEdited, 0) AS PostsEdited,
    ROUND((uem.Reputation / NULLIF(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - uem.UserCreationDate)), 0)), 2) AS ReputationPerDay,
    ROUND((uem.TotalPosts / NULLIF(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - uem.UserCreationDate)), 0)), 2) AS PostsPerDay
FROM UserEngagementMetrics uem
LEFT JOIN TopAnswerers ta ON uem.UserId = ta.OwnerUserId
LEFT JOIN (
    SELECT DISTINCT ON (OwnerUserId) 
        OwnerUserId,
        TagName AS TopTagName,
        TagPostCount AS TopTagPostCount,
        AvgTagScore AS TopTagScore
    FROM TagExpertise
    ORDER BY OwnerUserId, TagPostCount DESC
) te ON uem.UserId = te.OwnerUserId
LEFT JOIN VotingPatterns vp ON uem.UserId = vp.UserId
LEFT JOIN CommentActivity ca ON uem.UserId = ca.UserId
LEFT JOIN EditHistory eh ON uem.UserId = eh.UserId
WHERE uem.Reputation > 1000
GROUP BY
    uem.UserId,
    uem.DisplayName,
    uem.Reputation,
    uem.UserCreationDate,
    uem.TotalPosts,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.AvgPostScore,
    uem.TotalViews,
    uem.BadgeCount,
    uem.GoldBadges,
    uem.SilverBadges,
    uem.BronzeBadges,
    ta.AcceptedAnswers,
    ta.AvgAcceptedScore,
    ta.AcceptedRank,
    te.TopTagName,
    te.TopTagPostCount,
    te.TopTagScore,
    vp.UpvotesCast,
    vp.DownvotesCast,
    vp.FavoritesCast,
    vp.ActiveVotingDays,
    ca.CommentCount,
    ca.AvgCommentScore,
    eh.EditCount,
    eh.PostsEdited
ORDER BY uem.Reputation DESC, uem.BadgeCount DESC
LIMIT 500;