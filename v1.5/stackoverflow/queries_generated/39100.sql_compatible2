WITH
RecentQuestions AS (
    SELECT
        p.Id                      AS QuestionId,
        p.OwnerUserId             AS OwnerUserId,
        p.CreationDate            AS QuestionDate,
        p.Score                   AS QuestionScore,
        p.ViewCount               AS QuestionViews,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        )                        AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),

AnswerStats AS (
    SELECT
        a.ParentId               AS QuestionId,
        COUNT(*)                 AS AnswerCount,
        AVG(a.Score)             AS AvgAnswerScore,
        MAX(a.Score)             AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),

CommentsStats AS (
    SELECT
        c.PostId                 AS QuestionId,
        COUNT(*)                 AS CommentCount
    FROM Comments c
    WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    GROUP BY c.PostId
),

UserActivity AS (
    SELECT
        u.Id                      AS UserId,
        u.DisplayName             AS UserName,
        u.Reputation              AS Reputation,
        COUNT(DISTINCT rq.QuestionId) AS QuestionsAsked,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast
    FROM Users u
    LEFT JOIN RecentQuestions rq
        ON rq.OwnerUserId = u.Id
    LEFT JOIN Votes v
        ON v.UserId = u.Id
           AND v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TagBadges AS (
    SELECT
        rq.Tag                   AS Tag,
        COUNT(b.Id)              AS TagBadgeCount
    FROM RecentQuestions rq
    JOIN Badges b
      ON b.UserId = rq.OwnerUserId
     AND b.TagBased = TRUE
    GROUP BY rq.Tag
),

RankedTags AS (
    SELECT
        rq.Tag,
        COUNT(DISTINCT rq.QuestionId)                AS QuestionCount,
        SUM(coalesce(as_.AnswerCount,0))             AS TotalAnswers,
        ROUND(AVG(coalesce(as_.AvgAnswerScore,0)),2)  AS AvgAnswerScore,
        MAX(coalesce(as_.MaxAnswerScore,0))           AS TopAnswerScore,
        SUM(coalesce(rq.QuestionViews,0))            AS TotalViews,
        SUM(coalesce(cs.CommentCount,0))             AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT rq.QuestionId) DESC) AS TagRank
    FROM RecentQuestions rq
    LEFT JOIN AnswerStats as_ ON as_.QuestionId = rq.QuestionId
    LEFT JOIN CommentsStats cs ON cs.QuestionId = rq.QuestionId
    GROUP BY rq.Tag
)

SELECT
    rt.Tag,
    rt.TagRank,
    rt.QuestionCount,
    rt.TotalAnswers,
    rt.AvgAnswerScore,
    rt.TopAnswerScore,
    rt.TotalComments,
    rt.TotalViews,
    tb.TagBadgeCount,
    ua.QuestionsAsked,
    ua.UpVotesCast,
    ua.Reputation,
    DENSE_RANK() OVER (ORDER BY rt.TotalViews DESC) AS ViewPopularityRank
FROM RankedTags rt
LEFT JOIN TagBadges tb
  ON tb.Tag = rt.Tag
LEFT JOIN RecentQuestions rq
  ON rq.Tag = rt.Tag
LEFT JOIN UserActivity ua
  ON ua.UserId = rq.OwnerUserId
WHERE rt.TagRank <= 25
ORDER BY rt.TagRank;