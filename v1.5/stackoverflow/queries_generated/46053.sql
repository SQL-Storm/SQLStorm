-- {"query": "46053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 121582, "output_tokens": 98418} 

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score > 5
    GROUP BY p.OwnerUserId, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
AnswerPerformance AS (
    SELECT 
        a.OwnerUserId,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId = a.Id THEN a.Id END) as AcceptedCount,
        AVG(a.Score) as AvgAnswerScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) as MedianScore
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND a.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY a.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) as TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) as BronzeBadges,
        MAX(Date) as LastBadgeDate
    FROM Badges
    WHERE Date >= TIMESTAMP '2020-01-01'
    GROUP BY UserId
),
TagEngagement AS (
    SELECT 
        p.OwnerUserId,
        t.tag,
        COUNT(DISTINCT p.Id) as PostsInTag,
        AVG(p.Score) as TagAvgScore
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as t(tag)
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId, t.tag
),
TopTagsPerUser AS (
    SELECT 
        OwnerUserId,
        tag as TopTag,
        PostsInTag,
        TagAvgScore,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY PostsInTag DESC, TagAvgScore DESC) as TagRank
    FROM TagEngagement
),
InteractionMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) as CommentsReceived,
        COUNT(DISTINCT v.Id) as TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as Downvotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId
)
SELECT 
    tqa.OwnerUserId,
    tqa.DisplayName,
    tqa.QuestionCount,
    ROUND(tqa.AvgScore::numeric, 2) as AvgQuestionScore,
    tqa.TotalViews,
    COALESCE(ap.AnswerCount, 0) as AnswerCount,
    COALESCE(ap.AcceptedCount, 0) as AcceptedAnswers,
    ROUND(COALESCE(ap.AvgAnswerScore, 0)::numeric, 2) as AvgAnswerScore,
    COALESCE(ubs.TotalBadges, 0) as TotalBadges,
    COALESCE(ubs.GoldBadges, 0) as Gold,
    COALESCE(ubs.SilverBadges, 0) as Silver,
    COALESCE(ubs.BronzeBadges, 0) as Bronze,
    COALESCE(ttu.TopTag, 'None') as PrimaryTag,
    COALESCE(ttu.PostsInTag, 0) as PostsInPrimaryTag,
    COALESCE(im.CommentsReceived, 0) as CommentsReceived,
    COALESCE(im.Upvotes, 0) as Upvotes,
    COALESCE(im.Downvotes, 0) as Downvotes,
    ROUND(
        CASE 
            WHEN COALESCE(im.Upvotes, 0) + COALESCE(im.Downvotes, 0) > 0 
            THEN COALESCE(im.Upvotes, 0)::numeric / (COALESCE(im.Upvotes, 0) + COALESCE(im.Downvotes, 0))
            ELSE 0 
        END * 100, 2
    ) as PositiveVotePercentage,
    ROUND((tqa.QuestionCount + COALESCE(ap.AnswerCount, 0))::numeric / 
        GREATEST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - TIMESTAMP '2020-01-01')) / 86400, 1), 2) as AvgPostsPerDay
FROM TopQuestionAuthors tqa
LEFT JOIN AnswerPerformance ap ON tqa.OwnerUserId = ap.OwnerUserId
LEFT JOIN UserBadgeStats ubs ON tqa.OwnerUserId = ubs.UserId
LEFT JOIN TopTagsPerUser ttu ON tqa.OwnerUserId = ttu.OwnerUserId AND ttu.TagRank = 1
LEFT JOIN InteractionMetrics im ON tqa.OwnerUserId = im.OwnerUserId
ORDER BY 
    (tqa.QuestionCount * 2 + COALESCE(ap.AcceptedCount, 0) * 5 + COALESCE(ubs.GoldBadges, 0) * 10) DESC,
    tqa.TotalViews DESC
LIMIT 100;
