WITH UserAggregates AS (
    SELECT
        u.Id,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
        COUNT(c.Id) AS CommentCount,
        COUNT(b.Id) AS BadgeCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END ELSE 0 END) AS VoteBalance
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT ua.*,
        ROW_NUMBER() OVER (ORDER BY (QuestionScore + AnswerScore + BadgeCount * 10 + COALESCE(AvgQuestionViews, 0) / 100 + VoteBalance) DESC) AS UserRank,
        RANK() OVER (ORDER BY CommentCount DESC) AS CommentRank
    FROM UserAggregates ua
    WHERE BadgeCount > 0
),
UserPostsDetails AS (
    SELECT
        ua.Id AS UserId,
        p.Id AS PostId,
        p.Title,
        p.Tags,
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 4 THEN string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')
            ELSE CAST(ARRAY[] AS TEXT[])
        END AS TagArray,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        pl.RelatedPostId AS LinkedPostId
    FROM TopUsers ua
    LEFT JOIN Posts p ON ua.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1,2,4,5)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    WHERE ua.UserRank <= 100
),
UserTags AS (
    SELECT
        up.UserId,
        up.PostId,
        t.tag AS Tag
    FROM UserPostsDetails up
    LEFT JOIN LATERAL (
        SELECT unnest(up.TagArray) AS tag
    ) t ON TRUE
),
CorrelatedSub AS (
    SELECT
        up.UserId,
        COUNT(DISTINCT up.PostId) AS ActivePosts,
        CASE WHEN COUNT(ut.Tag) = 0 THEN NULL ELSE ARRAY_AGG(DISTINCT ut.Tag) END AS AllTags,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS EditCount
    FROM UserPostsDetails up
    LEFT JOIN PostHistory ph ON up.HistoryId = ph.Id
    LEFT JOIN UserTags ut ON up.UserId = ut.UserId AND up.PostId = ut.PostId
    GROUP BY up.UserId
),
FinalResult AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.QuestionScore,
        tu.AnswerScore,
        tu.BadgeCount,
        COALESCE(tu.AvgQuestionViews, 0) AS AvgQuestionViews,
        tu.VoteBalance,
        cs.ActivePosts,
        cs.EditCount,
        tu.UserRank,
        tu.CommentRank,
        CASE
            WHEN cs.AllTags IS NOT NULL THEN 'Tags: ' || array_to_string(cs.AllTags, ', ')
            ELSE 'No Tags'
        END AS TagSummary
    FROM TopUsers tu
    LEFT JOIN CorrelatedSub cs ON tu.Id = cs.UserId
    WHERE tu.UserRank <= 50 OR tu.CommentRank <= 50
)
SELECT * FROM FinalResult
UNION
SELECT
    CAST(NULL AS BIGINT) AS Id,
    'Summary' AS DisplayName,
    AVG(QuestionScore) AS QuestionScore,
    AVG(AnswerScore) AS AnswerScore,
    AVG(BadgeCount) AS BadgeCount,
    AVG(AvgQuestionViews) AS AvgQuestionViews,
    AVG(VoteBalance) AS VoteBalance,
    SUM(COALESCE(ActivePosts,0)) AS ActivePosts,
    SUM(COALESCE(EditCount,0)) AS EditCount,
    CAST(NULL AS INTEGER) AS UserRank,
    CAST(NULL AS INTEGER) AS CommentRank,
    'Overall Averages' AS TagSummary
FROM FinalResult
ORDER BY Id NULLS LAST, UserRank;