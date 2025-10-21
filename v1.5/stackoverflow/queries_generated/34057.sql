-- {"query": "34057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1388} 

WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
UserQuestionAnswerStats AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT q.Id) AS QuestionsCount,
        COUNT(DISTINCT a.Id) AS AnswersCount,
        COALESCE(SUM(a.Score),0) AS TotalAnswerScore,
        COALESCE(SUM(q.Score),0) AS TotalQuestionScore,
        AVG(q.Score) AS AvgQuestionScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        p.OwnerUserId,
        COUNT(p.Id) AS PostsWithTag
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName, t.Count, p.OwnerUserId
),
TopUsersByTag AS (
    SELECT 
        OwnerUserId AS UserId,
        TagName,
        COUNT(*) AS QuestionsPerTag
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    WHERE p.PostTypeId = 1
    GROUP BY OwnerUserId, TagName
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        EXTRACT(EPOCH FROM age(MAX(p.CreationDate), MIN(p.CreationDate)))/86400 AS ActiveDays,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostComplexStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.ViewCount,
        q.Score,
        q.AnswerCount,
        q.FavoriteCount,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinks,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedPosts
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.AnswerCount, q.FavoriteCount, a.Id, a.Score
),
UserTopQuestions AS (
    SELECT
        u.Id AS UserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        row_number() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
),
TopActiveUsers AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.ActiveDays,
        uas.TotalPosts,
        ubs.TotalBadges,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        uqa.QuestionsCount,
        uqa.AnswersCount,
        uqa.TotalAnswerScore,
        uqa.TotalQuestionScore
    FROM UserActivityWindow uas
    JOIN UserBadgeStats ubs ON uas.UserId = ubs.UserId
    JOIN UserQuestionAnswerStats uqa ON uas.UserId = uqa.UserId
    WHERE uas.TotalPosts > 50 AND ubs.GoldBadges > 0
    ORDER BY ubs.GoldBadges DESC, uas.TotalPosts DESC
    LIMIT 10
)

SELECT 
    tau.UserId,
    tau.DisplayName,
    tau.ActiveDays,
    tau.TotalPosts,
    tau.TotalBadges,
    tau.GoldBadges,
    tau.SilverBadges,
    tau.BronzeBadges,
    tau.QuestionsCount,
    tau.AnswersCount,
    tau.TotalAnswerScore,
    tau.TotalQuestionScore,
    utq.PostId AS TopQuestionId,
    utq.Title AS TopQuestionTitle,
    utq.Score AS TopQuestionScore,
    utq.ViewCount AS TopQuestionViewCount,
    utq.AnswerCount AS TopQuestionAnswerCount,
    pc.TotalEdits,
    pc.TotalComments,
    (
        SELECT COUNT(DISTINCT helper.Id)
        FROM Comments helper
        WHERE helper.UserId = tau.UserId AND helper.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    ) AS CommentsLast30Days
FROM TopActiveUsers tau
LEFT JOIN UserActivityWindow pc ON tau.UserId = pc.UserId
LEFT JOIN UserTopQuestions utq ON tau.UserId = utq.UserId AND utq.Rank = 1
ORDER BY tau.GoldBadges DESC, tau.TotalPosts DESC;
