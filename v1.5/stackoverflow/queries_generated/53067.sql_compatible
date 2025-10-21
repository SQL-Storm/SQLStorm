WITH QuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        p.CreationDate,
        p.Score AS QuestionScore,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TopTags AS (
    SELECT 
        Tag,
        COUNT(DISTINCT QuestionId) AS QuestionCount,
        AVG(QuestionScore) AS AvgQuestionScore,
        SUM(ViewCount) AS TotalViews
    FROM QuestionTags
    GROUP BY Tag
    HAVING COUNT(DISTINCT QuestionId) > 1000
    ORDER BY QuestionCount DESC
    LIMIT 50
),
TagAnswers AS (
    SELECT 
        qt.Tag,
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        v.VoteTypeId,
        COUNT(v.Id) AS VoteCount
    FROM QuestionTags qt
    JOIN Posts a ON a.ParentId = qt.QuestionId
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY qt.Tag, a.Id, a.OwnerUserId, a.Score, a.CreationDate, v.VoteTypeId
),
AnswerStats AS (
    SELECT 
        Tag,
        OwnerUserId,
        COUNT(AnswerId) AS AnswerCount,
        AVG(AnswerScore) AS AvgAnswerScore,
        MAX(AnswerDate) AS LatestAnswerDate,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM TagAnswers
    GROUP BY Tag, OwnerUserId
    HAVING COUNT(AnswerId) > 10
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
RankedAnswerers AS (
    SELECT 
        stats.Tag,
        stats.OwnerUserId,
        stats.AnswerCount,
        stats.AvgAnswerScore,
        stats.LatestAnswerDate,
        stats.Upvotes,
        stats.Downvotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY stats.Tag ORDER BY stats.AnswerCount DESC, stats.AvgAnswerScore DESC) AS Rank
    FROM AnswerStats AS stats
    LEFT JOIN UserBadges ub ON stats.OwnerUserId = ub.UserId
),
TopComments AS (
    SELECT 
        c.PostId,
        MAX(c.Score) AS TopCommentScore,
        COUNT(c.Id) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
FinalResults AS (
    SELECT 
        tt.Tag,
        tt.QuestionCount,
        tt.AvgQuestionScore,
        tt.TotalViews,
        u.DisplayName AS TopAnswerer,
        ra.AnswerCount,
        ra.AvgAnswerScore,
        ra.LatestAnswerDate,
        ra.Upvotes,
        ra.Downvotes,
        ra.GoldBadges,
        ra.SilverBadges,
        ra.BronzeBadges,
        AVG(tc.TopCommentScore) AS AvgTopCommentScore,
        SUM(tc.CommentCount) AS TotalComments
    FROM TopTags tt
    JOIN RankedAnswerers ra ON tt.Tag = ra.Tag AND ra.Rank = 1
    JOIN Users u ON ra.OwnerUserId = u.Id
    JOIN TagAnswers ta ON tt.Tag = ta.Tag AND ra.OwnerUserId = ta.OwnerUserId
    LEFT JOIN TopComments tc ON ta.AnswerId = tc.PostId
    GROUP BY 
        tt.Tag,
        tt.QuestionCount,
        tt.AvgQuestionScore,
        tt.TotalViews,
        u.DisplayName,
        ra.AnswerCount,
        ra.AvgAnswerScore,
        ra.LatestAnswerDate,
        ra.Upvotes,
        ra.Downvotes,
        ra.GoldBadges,
        ra.SilverBadges,
        ra.BronzeBadges
)
SELECT * 
FROM FinalResults
ORDER BY QuestionCount DESC, AvgAnswerScore DESC;