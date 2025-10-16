WITH parsed_tags AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        unnest(COALESCE(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><'), ARRAY[]::text[])) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
user_post_stats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(COUNT(DISTINCT q.Id), 0) AS QuestionCount,
        COALESCE(COUNT(DISTINCT a.Id), 0) AS AnswerCount,
        COALESCE(SUM(q.Score), 0) + COALESCE(SUM(a.Score), 0) AS TotalScore,
        COALESCE(AVG(q.Score), 0) AS AvgQuestionScore,
        COALESCE(SUM(CASE WHEN a.AcceptedAnswerId IS NOT NULL AND a.Id = a.AcceptedAnswerId THEN 1 ELSE 0 END), 0) AS AcceptedAnswers
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
badge_ranks AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.TagBased = TRUE
),
comment_activity AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        SUM(c.Score) AS CommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
),
vote_activity AS (
    SELECT 
        v.PostId,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetUpvotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
posts_vote_summary AS (
    SELECT 
        p.OwnerUserId,
        SUM(COALESCE(va.VoteCount,0)) AS TotalVotesReceived,
        SUM(COALESCE(va.NetUpvotes,0)) AS NetUpvotes
    FROM Posts p
    LEFT JOIN vote_activity va ON va.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
top_users AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalScore,
        ups.AvgQuestionScore,
        ups.AcceptedAnswers,
        br.BadgeRank AS TopBadgeRank,
        ca.CommentCount,
        ca.CommentScore,
        ca.LastCommentDate,
        COALESCE(pvs.NetUpvotes, 0) AS NetUpvotes,
        (ups.TotalScore + COALESCE(ca.CommentScore, 0) * 0.5 + COALESCE(pvs.NetUpvotes, 0) * 2 + ups.AcceptedAnswers * 10) AS ActivityScore,
        CASE 
            WHEN ups.QuestionCount > 0 THEN 
                (SELECT STRING_AGG(pt.Tag, ',') FROM parsed_tags pt WHERE pt.OwnerUserId = ups.UserId GROUP BY pt.OwnerUserId)
            ELSE NULL
        END AS TopTags,
        RANK() OVER (ORDER BY (ups.TotalScore + COALESCE(ca.CommentScore, 0) * 0.5 + COALESCE(pvs.NetUpvotes, 0) * 2 + ups.AcceptedAnswers * 10) DESC) AS GlobalRank
    FROM user_post_stats ups
    LEFT JOIN badge_ranks br ON br.UserId = ups.UserId AND br.BadgeRank = 1
    LEFT JOIN comment_activity ca ON ca.UserId = ups.UserId
    LEFT JOIN posts_vote_summary pvs ON pvs.OwnerUserId = ups.UserId
    WHERE ups.TotalScore > 100 OR br.UserId IS NOT NULL
    ORDER BY ActivityScore DESC
    LIMIT 100
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.AvgQuestionScore,
    tu.AcceptedAnswers,
    tu.TopBadgeRank,
    tu.CommentCount,
    tu.CommentScore,
    tu.LastCommentDate,
    tu.NetUpvotes,
    tu.ActivityScore,
    tu.TopTags,
    tu.GlobalRank
FROM top_users tu
UNION ALL
SELECT 
    NULL AS UserId,
    'Summary' AS DisplayName,
    SUM(tu.QuestionCount) AS QuestionCount,
    SUM(tu.AnswerCount) AS AnswerCount,
    SUM(tu.TotalScore) AS TotalScore,
    AVG(tu.AvgQuestionScore) AS AvgQuestionScore,
    SUM(tu.AcceptedAnswers) AS AcceptedAnswers,
    NULL AS TopBadgeRank,
    SUM(COALESCE(tu.CommentCount,0)) AS CommentCount,
    SUM(COALESCE(tu.CommentScore,0)) AS CommentScore,
    NULL AS LastCommentDate,
    SUM(COALESCE(tu.NetUpvotes,0)) AS NetUpvotes,
    SUM(tu.ActivityScore) AS ActivityScore,
    NULL AS TopTags,
    NULL AS GlobalRank
FROM top_users tu;