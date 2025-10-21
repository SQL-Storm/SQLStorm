-- {"query": "34067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 943} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        COALESCE(SUM(vt.UpVotes),0) AS TotalUpVotes,
        COALESCE(SUM(vt.DownVotes),0) AS TotalDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) vt ON vt.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
), 
TopTagsPerUser AS (
    SELECT 
        pu.OwnerUserId AS UserId,
        tag.TagName,
        COUNT(*) AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY pu.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts pu
    CROSS JOIN LATERAL unnest(string_to_array(substring(pu.Tags, 2, length(pu.Tags) - 2), '><')) AS tag(TagName)
    WHERE pu.OwnerUserId IS NOT NULL
    GROUP BY pu.OwnerUserId, tag.TagName
),
UserTopTag AS (
    SELECT UserId, TagName, TagUseCount
    FROM TopTagsPerUser
    WHERE rn = 1
),
RecentQuestionStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.CreationDate >= cast('2024-10-01' as date) - interval '30 days') AS RecentQuestions,
        AVG(p.Score) FILTER (WHERE p.CreationDate >= cast('2024-10-01' as date) - interval '30 days') AS AvgRecentQuestionScore,
        AVG(p.ViewCount) FILTER (WHERE p.CreationDate >= cast('2024-10-01' as date) - interval '30 days') AS AvgRecentQuestionViews
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
AnswerPerformance AS (
    SELECT 
        a.OwnerUserId AS UserId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 END) AS AcceptedAnswerCount
    FROM Posts a
    LEFT JOIN Posts q ON q.AcceptedAnswerId = a.Id
    WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),
UserCommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(*) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.PostId) AS CommentedPosts
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.TotalPostScore,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.BadgeCount,
    ua.LastPostDate,
    utt.TagName AS TopTag,
    utt.TagUseCount,
    rq.RecentQuestions,
    rq.AvgRecentQuestionScore,
    rq.AvgRecentQuestionViews,
    ap.TotalAnswers,
    ap.AvgAnswerScore,
    ap.AcceptedAnswerCount,
    cca.TotalComments,
    cca.AvgCommentScore,
    cca.CommentedPosts
FROM UserActivity ua
LEFT JOIN UserTopTag utt ON utt.UserId = ua.UserId
LEFT JOIN RecentQuestionStats rq ON rq.UserId = ua.UserId
LEFT JOIN AnswerPerformance ap ON ap.UserId = ua.UserId
LEFT JOIN UserCommentActivity cca ON cca.UserId = ua.UserId
WHERE ua.TotalPosts > 20
ORDER BY ua.TotalPostScore DESC
LIMIT 100;